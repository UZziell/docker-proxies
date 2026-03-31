#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_OR_CLIENT="${1:-}"
DOMAIN="${2:-}"
RESOLVER="${3:-}"
TIMEOUT="${4:-60}"
SLIP_PLUS="${5:-}"
INSTANCES="${6:-5}"

export SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS=60000
export BASE_PORT="${7:-8003}"

SLIP_PID=""
declare -a CLIENT_PIDS=()

sleep_with_counter() {
	local seconds=$1
	local i=1

	while [[ $i -lt "$seconds" ]]; do
		printf "\rSleeping: %d / %d seconds%s" "$i" "$seconds" "$2"
		sleep 1
		((i++))
	done
	printf "\rSleeping: %d / %d seconds%s" "$i" "$seconds" "$2"
}

log() {
	echo "INFO $(date +%FT%H:%M:%S) | $*"
}

kill_port() {
	local proto="$1"
	local port="$2"

	ss -${proto}lpn |
		grep -w ":$port" |
		grep -Po 'pid=\d+' |
		grep -Po '\d+' |
		sort -u |
		xargs -r kill -9 >/dev/null 2>&1 || true
}

cleanup() {
	log "shutdown requested, cleaning up..."

	# Kill the single SLIP_PID if still set (for server or legacy client)
	if [[ -n "${SLIP_PID:-}" ]] && kill -0 "$SLIP_PID" 2>/dev/null; then
		log "killing slipstream pid $SLIP_PID"
		kill -TERM "$SLIP_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$SLIP_PID" 2>/dev/null || true
	fi

	case "$SERVER_OR_CLIENT" in
	server)
		kill_port u 53
		;;
	client)
		kill_port t "${BASE_PORT}"
		;;
	client-multi)
		# Kill all self-healing client loops
		if [[ ${#CLIENT_PIDS[@]} -gt 0 ]]; then
			for PID in "${CLIENT_PIDS[@]}"; do
				if kill -0 "$PID" 2>/dev/null; then
					log "killing client loop PID $PID"
					kill -TERM "$PID" 2>/dev/null || true
					sleep 1
					kill -9 "$PID" 2>/dev/null || true
				fi
			done
		fi

		# Kill all TCP ports used by clients
		if [[ ${#RESOLVERS[@]} -gt 0 ]]; then
			for i in "${!RESOLVERS[@]}"; do
				PORT=$((BASE_PORT + i))
				kill_port t "$PORT"
			done
		else
			# fallback to original BASE_PORT if no resolvers set yet
			kill_port t "${BASE_PORT}"
		fi
		;;
	esac

	log "cleanup complete"
}

trap cleanup EXIT SIGINT SIGTERM

case "$SERVER_OR_CLIENT" in
server)
	while true; do
		kill_port u 53

		log "running server | Domain: $DOMAIN"
		timeout "$TIMEOUT" \
			"./bin/slipstream-server${SLIP_PLUS}" \
			--dns-listen-port 53 \
			--target-address 127.0.0.1:2080 \
			--domain "$DOMAIN" \
			--cert ./cert.pem \
			--key ./key.pem &

		SLIP_PID=$!
		wait "$SLIP_PID" || true

		log "timeout"
	done
	;;

client)
	declare -a RESOLVERS=()

	if [[ -n "$RESOLVER" ]]; then
		IFS=',' read -r -a ips <<<"$RESOLVER"
		for ip in "${ips[@]}"; do
			RESOLVERS+=(--resolver "$ip")
		done
	else
		while read -r ip; do
			RESOLVERS+=(--resolver "$ip")
		done < <(
			grep -i slipstream ../scripts/data/RESULTS.txt |
				awk -F'|' '{gsub(/ /,"",$0); print $2 "|" $3}' |
				sed 's/total=//;s/s.*//' |
				sort -n -t'|' -k2 |
				head -n "$INSTANCES" |
				awk -F'|' '{print $1}'
		)
	fi

	while true; do
		kill_port t BASE_PORT

		log "running client | DOMAIN: $DOMAIN | TIMEOUT: ${TIMEOUT} | RESOLVERS: ${RESOLVERS[*]}"
		"./bin/slipstream-client${SLIP_PLUS}" \
			--tcp-listen-port ${BASE_PORT} \
			--domain "$DOMAIN" \
			--keep-alive-interval ${SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS} \
			--congestion-control bbr \
			"${RESOLVERS[@]}" &

		SLIP_PID=$!
		# log "$SLIP_PID running! sleeping for $TIMEOUT seconds"

		sleep "$TIMEOUT"

		log "timeout! stopping $SLIP_PID"
		kill -TERM "$SLIP_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$SLIP_PID" 2>/dev/null || true
	done
	;;

client-multi)
	declare -a RESOLVERS=()

	if [[ -n "$RESOLVER" ]]; then
		IFS=',' read -r -a ips <<<"$RESOLVER"
		for ip in "${ips[@]}"; do
			RESOLVERS+=("$ip")
		done
	else
		mapfile -t RESOLVERS < <(
			grep -i Slipstream ../scripts/data/RESULTS.txt |
				awk -F'|' '{gsub(/ /,"",$0); print $2 "|" $3}' |
				sed 's/total=//;s/s.*//' |
				sort -n -t'|' -k2 |
				head -n "$INSTANCES" |
				awk -F'|' '{print $1}'
		)
	fi

	if [[ ${#RESOLVERS[@]} -eq 0 ]]; then
		log "No resolvers found in RESULTS.txt"
		exit 1
	fi

	log "Starting top ${#RESOLVERS[@]} slipstream clients | DOMAIN: $DOMAIN | TIMEOUT: ${TIMEOUT} | RESOLVERS: ${RESOLVERS[*]}"

	## Run multiple instances of Splitstream-client
	for i in "${!RESOLVERS[@]}"; do
		RES="${RESOLVERS[$i]}"
		PORT=$((BASE_PORT + i))
		(
			# Self-healing loop per client
			while true; do
				kill_port t "$PORT"
				log "Starting client on port $PORT using resolver $RES"
				"./bin/slipstream-client${SLIP_PLUS}" \
					--tcp-listen-port "$PORT" \
					--domain "$DOMAIN" \
					--keep-alive-interval ${SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS} \
					--congestion-control bbr \
					--resolver "$RES" &

				CLIENT_PID=$!
				log "Client PID $CLIENT_PID started on port $PORT"
				wait "$CLIENT_PID" || true
				log "Client PID $CLIENT_PID exited on port $PORT, restarting..."
				sleep $((RANDOM % 10 + 1))
			done
		) &
		LOOP_PID=$!
		CLIENT_PIDS+=("$LOOP_PID")
	done

	wait
	;;

*)
	echo "Usage: $0 {server|client|client-multi} DOMAIN [RESOLVERS(comma-seperated)] [TIMEOUT]"
	exit 1
	;;
esac

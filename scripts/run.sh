#!/usr/bin/env bash
set -Eeuo pipefail

export SERVER_OR_CLIENT="${1}"
export TUNNEL_TYPE="${2}"
export TUNNEL_DOMAIN="${3}"
export RESOLVER="${4:-}"
export TIMEOUT="${5:-60}"
export SLIP_PLUS="${6:-}"
export INSTANCES="${7:-5}"

export SLIPSTREAM_PATH="../slipstream-rust"
export DNSTT_PATH="../dnstt"
export VAYDNS_PATH="../vaydns"

export SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS=60000
export VAYDNS_RECORD_TYPE=""

export SERVER_LISTEN_PORT=53
export BASE_CLIENT_LISTEN_PORT="${7:-8003}"
export TUNNEL_PID=""

declare -a CLIENT_PIDS=()

log() {
	echo "[INFO] $(date +%FT%H:%M:%S) | $*"
}

print_help() {
	echo "*********************"
	echo "* DNS Tunnel Runner *"
	echo "*********************"
	echo "Usage:"
	echo "  ./run.sh [SERVER_OR_CLIENT=server/client/client-multi] [TUNNEL_TYPE=slip/dnstt/vaydns(-VAYDNS_RECORD_TYPE)] [TUNNEL_DOMAIN] [RESOLVER(client only)] [TIMEOUT(optional)] [SLIP_PLUS(optional)] [INSTANCES(multi-client only)]"
	echo "Example: "
	echo "  ./run.sh client slip t.example.com 9.9.9.9 '-plus'"
	echo "  ./run.sh server dnstt tt.example.com 9.9.9.9 90"
	echo "  ./run.sh client vaydns-txt t.example.com 9.9.9.9"
	echo "  ./run.sh client vaydns-cname t.example.com 9.9.9.9"
	exit 1
}

check_arguments() {
	# Check tunnel type argument and set vaydns record type
	if [[ $TUNNEL_TYPE =~ ^vaydns$ ]]; then
		echo "[INFO] [VAYDNS_RECORD_TYPE] not set. Setting 'txt' as default"
		export VAYDNS_RECORD_TYPE="txt"
	elif [[ $TUNNEL_TYPE =~ ^vaydns-[a-z]+ ]]; then
		VAYDNS_RECORD_TYPE=$(echo "$TUNNEL_TYPE" | cut -d'-' -f2)
		export VAYDNS_RECORD_TYPE
		export TUNNEL_TYPE='vaydns'
		if [[ ! "$VAYDNS_RECORD_TYPE" =~ ^(txt|cname|a|aaaa|mx|ns|srv)$ ]]; then
			echo "[FATAL] [VAYDNS_RECORD_TYPE] should be one of (txt, cname, a, aaaa, mx, ns, srv). (Input: '${VAYDNS_RECORD_TYPE}')"
			print_help
		fi
	fi
	if [[ ! $SERVER_OR_CLIENT =~ ^(server|client|client-multi)$ ]]; then
		echo "[FATAL] [SERVER_OR_CLIENT] should be one of 'server', 'client', or 'client-multi'. (Input: '${SERVER_OR_CLIENT}')"
		print_help
	elif [[ ! $TUNNEL_TYPE =~ ^(slip|dnstt|vaydns)$ ]]; then
		echo "[FATAL] [TUNNEL_TYPE] should be one of 'slip', 'dnstt', or 'vaydns'. (Input: '${TUNNEL_TYPE}')"
		print_help
	elif [[ ! "$TUNNEL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\.?$ ]]; then
		echo "[FATAL] '${TUNNEL_DOMAIN}' is not a valid domain."
		print_help
	elif [[ -z $RESOLVER ]] && [[ $SERVER_OR_CLIENT =~ ^(client|client-multi)$ ]] && [[ $TUNNEL_TYPE != 'slip' ]]; then
		echo "[FATAL] [RESOLVER] is empty."
		print_help
	elif [[ ! $TIMEOUT =~ ^[0-9]+$ ]]; then
		echo "[FATAL] [TIMEOUT] should be an integer. (Input: '${TIMEOUT}')"
		print_help
	elif [[ ! $INSTANCES =~ ^[0-9]+$ ]]; then
		echo "[FATAL] [INSTANCES] should be an integer. (Input: '${INSTANCES}')"
		print_help
	fi
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

	# Kill the single TUNNEL_PID
	if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
		log "killing ${TUNNEL_TYPE} pid $TUNNEL_PID"
		kill -TERM "$TUNNEL_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$TUNNEL_PID" 2>/dev/null || true
	fi

	case "$SERVER_OR_CLIENT" in
	server)
		kill_port u $SERVER_LISTEN_PORT
		;;
	client)
		kill_port t "${BASE_CLIENT_LISTEN_PORT}"
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
				PORT=$((BASE_CLIENT_LISTEN_PORT + i))
				kill_port t "$PORT"
			done
		else
			# fallback to original BASE_CLIENT_LISTEN_PORT if no resolvers set yet
			kill_port t "${BASE_CLIENT_LISTEN_PORT}"
		fi
		;;
	esac

	log "cleanup complete"
}

run_server() {
	while true; do
		kill_port u $SERVER_LISTEN_PORT

		log "running server | Domain: $TUNNEL_DOMAIN"

		case "$TUNNEL_TYPE" in
		slip)
			timeout "$TIMEOUT" "./bin/slipstream-server${SLIP_PLUS}" \
				--dns-listen-port $SERVER_LISTEN_PORT \
				--target-address 127.0.0.1:2080 \
				--domain "$TUNNEL_DOMAIN" \
				--cert ./cert.pem \
				--key ./key.pem &
			;;
		dnstt) ;;
		vaydns) ;;
		esac

		TUNNEL_PID=$!
		wait "$TUNNEL_PID" || true

		log "timeout"
	done
}
run_client() {
	while true; do
		kill_port t "${BASE_CLIENT_LISTEN_PORT}"
		log "running '${TUNNEL_TYPE} ${VAYDNS_RECORD_TYPE}' client | DOMAIN: $TUNNEL_DOMAIN | TIMEOUT: ${TIMEOUT} | RESOLVER(S): ${RESOLVER}"
		case "$TUNNEL_TYPE" in
		slip)
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
					grep -i slip ./data/RESULTS.txt |
						awk -F'|' '{gsub(/ /,"",$0); print $2 "|" $3}' |
						sed 's/total=//;s/s.*//' |
						sort -n -t'|' -k2 |
						head -n "$INSTANCES" |
						awk -F'|' '{print $1}'
				)
			fi
			"${SLIPSTREAM_PATH}/bin/slipstream-client${SLIP_PLUS}" \
				--tcp-listen-port "${BASE_CLIENT_LISTEN_PORT}" \
				--domain "$TUNNEL_DOMAIN" \
				--keep-alive-interval ${SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS} \
				--congestion-control bbr \
				"${RESOLVERS[@]}" &

			;;
		dnstt)
			"$DNSTT_PATH/bin/dnstt-client-linux-amd64" \
				-udp "${RESOLVER}:53" \
				-utls Chrome \
				-pubkey-file "$DNSTT_PATH/data/server.pub" \
				"${TUNNEL_DOMAIN}" "127.0.0.1:$BASE_CLIENT_LISTEN_PORT" &
			;;
		vaydns)
			"$VAYDNS_PATH/bin/vaydns-client" \
				-udp "${RESOLVER}:53" \
				-pubkey-file "$VAYDNS_PATH/data/server.pub" \
				-utls Firefox \
				-record-type "${VAYDNS_RECORD_TYPE}" \
				-idle-timeout 10s \
				-keepalive 2s \
				-queue-size 512 \
				-kcp-window-size 0 \
				-listen "127.0.0.1:${BASE_CLIENT_LISTEN_PORT}" \
				--domain "${TUNNEL_DOMAIN}" &
			;;
		esac
		TUNNEL_PID=$!

		sleep "$TIMEOUT"
		log "timeout! stopping $TUNNEL_PID"
		kill -TERM "$TUNNEL_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$TUNNEL_PID" 2>/dev/null || true
	done
}

## Main ##
trap cleanup EXIT SIGINT SIGTERM

check_arguments

# Run client/server
case "$SERVER_OR_CLIENT" in
server)
	run_server
	;;

client)
	run_client
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
			grep -i slip ./data/RESULTS.txt |
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

	log "Starting top ${#RESOLVERS[@]} slipstream clients | DOMAIN: $TUNNEL_DOMAIN | TIMEOUT: ${TIMEOUT} | RESOLVERS: ${RESOLVERS[*]}"

	## Run multiple instances of Splitstream-client
	for i in "${!RESOLVERS[@]}"; do
		RES="${RESOLVERS[$i]}"
		PORT=$((BASE_CLIENT_LISTEN_PORT + i))
		(
			# Self-healing loop per client
			while true; do
				kill_port t "$PORT"
				log "Starting client on port $PORT using resolver $RES"
				"./bin/slipstream-client${SLIP_PLUS}" \
					--tcp-listen-port "$PORT" \
					--domain "$TUNNEL_DOMAIN" \
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

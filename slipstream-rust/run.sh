#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_OR_CLIENT="${1:-}"
DOMAIN="${2:-}"
RESOLVER="${3:-}"
TIMEOUT="${4:-30}"

SLIP_PID=""

sleep_with_counter() {
  local seconds=$1
  local i=0

  while [ $i -lt "$seconds" ]; do
    printf "\rSleeping: %d / %d seconds" "$i" "$seconds"
    sleep 1
    ((i++))
  done
  printf "\rSleeping: %d / %d seconds\n" "$seconds" "$seconds"
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
		kill_port t 8003
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
			./slipstream-server \
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
		RESOLVERS+=(--resolver "$RESOLVER")
	else
		while read -r ip; do
			RESOLVERS+=(--resolver "$ip")
		done < <(
			grep -i slipstream ../scripts/data/RESULTS.txt |
				grep -Po '\d+\.\d+\.\d+\.\d{1,3} | sort -u | shuf'
		)
	fi

	while true; do
		kill_port t 8003

		log "running client | DOMAIN: $DOMAIN | TIMEOUT: ${TIMEOUT} | RESOLVERS: ${RESOLVERS[*]}"
		./slipstream-client \
			--tcp-listen-port 8003 \
			--domain "$DOMAIN" \
			--keep-alive-interval 30 \
			"${RESOLVERS[@]}" &

		SLIP_PID=$!
		log "$SLIP_PID running! sleeping for $TIMEOUT seconds"

		sleep "$TIMEOUT"

		log "timeout! stopping $SLIP_PID"
		kill -TERM "$SLIP_PID" 2>/dev/null || true
		sleep 1
		kill -9 "$SLIP_PID" 2>/dev/null || true
	done
	;;

*)
	echo "Usage: $0 {server|client} DOMAIN [RESOLVER] [TIMEOUT]"
	exit 1
	;;
esac

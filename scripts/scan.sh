#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Positional arguments and Configuration
export PARALLEL_JOBS="${1:-20}"
export TUNNEL_TYPE="${2}"
export SOCKS_USER_PASS="${3}"
export TEST_TUNNEL_DOMAIN="${4}"
export TEST_RESOLVER_DOMAIN="${5:-}"
export RESOLVER_FILE="${6:-./dns-ir.txt}"
export SLIP_PLUS="${7:-}"

export DATA_DIR="./data"
export RESPONSIVE_RESOLVER_FILE="${DATA_DIR}/dns-working.txt"
export RESULTS_FILE="${DATA_DIR}/RESULTS.txt"
export SLIPSTREAM_PATH="../slipstream-rust"
export DNSTT_PATH="../dnstt"
export VAYDNS_PATH="../vaydns"
export HOSTNAME=$(hostname)
export TIMEOUT=25
export CURL_TIMEOUT=24
export TEST_RESOLVER_TIMEOUT=5
export SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS=30000
export VAYDNS_RECORD_TYPE=""
declare -a DNS_COMMAND_OPTIONS
declare -a DNS_COMMAND_NS_QUERY

check_dependencies() {
	# Check Parallel
	if ! command -v parallel >/dev/null 2>&1; then
		echo "[WARNING] GNU Parallel not found. Attempting to install..."
		if command -v apt-get >/dev/null 2>&1; then
			sudo apt-get update && sudo apt-get install -y parallel
		else
			echo "[FATAL] This script requires GNU Parallel. Please install it manually."
			exit 1
		fi
	fi

	# Check DNS Utility
	for cmd in kdig dig drill dog; do
		if command -v "$cmd" >/dev/null 2>&1; then
			export DNS_UTILITY="$cmd"
			case "$DNS_UTILITY" in
			dig)
				DNS_COMMAND_OPTIONS+=("+short" "+fail")
				DNS_COMMAND_NS_QUERY+=("-t" "NS")
				if [ -z "$TEST_RESOLVER_DOMAIN" ]; then
					TEST_RESOLVER_DOMAIN=$(dig "${DNS_COMMAND_NS_QUERY[@]}" "${DNS_COMMAND_OPTIONS[@]}" "${TEST_TUNNEL_DOMAIN}")
				fi
				;;
			dog)
				DNS_COMMAND_OPTIONS+=("--short")
				DNS_COMMAND_NS_QUERY+=("--type=NS")
				if [ -z "$TEST_RESOLVER_DOMAIN" ]; then
					TEST_RESOLVER_DOMAIN=$(dog "${DNS_COMMAND_NS_QUERY[@]}" "${DNS_COMMAND_OPTIONS[@]}" "${TEST_TUNNEL_DOMAIN}")
				fi
				;;
			esac
			break
		fi
	done
}

print_help() {
	echo "**********************"
	echo "* DNS Tunnel Scanner *"
	echo "**********************"
	echo "Usage:"
	echo "  ./scan.sh [PARALLEL_JOBS] [TUNNEL_TYPE=slip/dnstt/vaydns(-VAYDNS_RECORD_TYPE)] [SOCKS_USER_PASS] [TEST_TUNNEL_DOMAIN] [TEST_RESOLVER_DOMAIN] [RESOLVER_FILE(optional)] [SLIP_PLUS(optional)]"
	echo "Example: "
	echo "  ./scan.sh 50 slip 'socks_username:socks_password' t.example.com ns.example.com ./dns-custom.txt '-plus'"
	echo "  ./scan.sh 16 dnstt 'socks_username:socks_password' t.example.com ns2.example.com ./dns-custom.txt"
	echo "  ./scan.sh 8 vaydns-txt 'socks_username:socks_password' t.example.com ns2.example.com ./dns-custom.txt"
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
	if [ -z "$DNS_UTILITY" ]; then
		echo "[FATAL] No DNS utility found (dig, kdig, drill, or dog). Install 'dnsutils' or 'knot-dnsutils'."
		print_help
	elif [[ ! $PARALLEL_JOBS =~ ^-?[0-9]+$ ]]; then
		echo "[FATAL] [PARALLEL_JOBS] should be an integer. (Input: '${PARALLEL_JOBS}')"
		print_help
	elif [[ ! $TUNNEL_TYPE =~ ^(slip|dnstt|vaydns)$ ]]; then
		echo "[FATAL] [TUNNEL_TYPE] should be one of 'slip', 'dnstt', or 'vaydns'. (Input: '${TUNNEL_TYPE}')"
		print_help
	elif ! echo "$SOCKS_USER_PASS" | grep -q ':'; then
		echo "[FATAL] [SOCKS_USER_PASS] should follow the format 'socks_username:socks_password'. (Input: '${SOCKS_USER_PASS}')"
		print_help
	elif [[ ! "$TEST_TUNNEL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\.?$ ]]; then
		echo "[FATAL] '${TEST_TUNNEL_DOMAIN}' is not a valid test domain."
		print_help
	elif [[ ! "$TEST_RESOLVER_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\.?$ ]]; then
		echo "[FATAL] Could not resolve NS record for '${TEST_TUNNEL_DOMAIN}'. Try setting it as positonal argument "
		print_help
	elif [[ ! -s $RESOLVER_FILE ]]; then
		echo "[FATAL] Input resolver file '${RESOLVER_FILE}', does not exist or is empty "
		print_help
	fi

}

test_resolver() {
	local RESOLVER=$1
	declare -a DNS_COMMAND_OPTIONS=$2
	declare -a DNS_COMMAND_NS_QUERY=$3
	# test A record
	# timeout "$TEST_RESOLVER_TIMEOUT" "$DNS_UTILITY" "${DNS_COMMAND_OPTIONS[@]}" "@${RESOLVER}" "$TEST_RESOLVER_DOMAIN" >/dev/null 2>&1 && echo "$RESOLVER" >>"$RESPONSIVE_RESOLVER_FILE"
	timeout "$TEST_RESOLVER_TIMEOUT" "$DNS_UTILITY" "${DNS_COMMAND_OPTIONS[@]}" "@${RESOLVER}" "$TEST_RESOLVER_DOMAIN" 2>/dev/null |
		grep -vE '(^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^169\.254\.)' |
		grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null 2>&1 &&
		echo "$RESOLVER" >>"$RESPONSIVE_RESOLVER_FILE" #&& \
	# echo "server=${RESOLVER}" >>"${DATA_DIR}/masq.txt"

	# test NS record
	# timeout "$TEST_RESOLVER_TIMEOUT" "$DNS_UTILITY" "${DNS_COMMAND_NS_QUERY[@]}" "${DNS_COMMAND_NS_QUERY[@]}" "@${RESOLVER}" "$TEST_TUNNEL_DOMAIN" >/dev/null 2>&1 && echo "$RESOLVER" >>"$RESPONSIVE_RESOLVER_FILE"
}

test_dns_tunnel() {
	local RESOLVER=$1
	local JOB_ID=$2
	local BASE_PORT=9000

	# log helper
	log_status() { echo -e "$1" >&2; }

	# wait for port helper
	wait_for_port() {
		local port=$1
		for i in {1..30}; do
			(ss -tlpn | grep -q ":${port}") >/dev/null 2>&1 && return 0
			sleep 0.2
		done
		return 1
	}

	local TUNNEL_PORT=$((BASE_PORT + JOB_ID))
	# TUNNEL_PORT=$((BASE_PORT + JOB_ID + 1000))
	case "$TUNNEL_TYPE" in
	slip)
		# (
		timeout $TIMEOUT "$SLIPSTREAM_PATH/bin/slipstream-client${SLIP_PLUS}" \
			--tcp-listen-port "$TUNNEL_PORT" \
			--resolver "$RESOLVER" \
			--keep-alive-interval ${SLIPSTREAM_KEEP_ALIVE_INTERVAL_MS} \
			--congestion-control bbr \
			--domain "${TEST_TUNNEL_DOMAIN}" >/dev/null 2>&1 &
		local PID=$!
		# ) &
		;;
	dnstt)
		# (
		timeout $TIMEOUT "$DNSTT_PATH/bin/dnstt-client-linux-amd64" \
			-udp "${RESOLVER}:53" \
			-utls Chrome \
			-pubkey-file "$DNSTT_PATH/data/server.pub" \
			"${TEST_TUNNEL_DOMAIN}" "127.0.0.1:$TUNNEL_PORT" >/dev/null 2>&1 &
		local PID=$!
		# ) &
		;;
	vaydns)
		# (
		timeout $TIMEOUT "$VAYDNS_PATH/bin/vaydns-client" \
			-udp "${RESOLVER}:53" \
			-pubkey-file "$VAYDNS_PATH/data/server.pub" \
			-utls Firefox \
			-record-type "${VAYDNS_RECORD_TYPE}" \
			-idle-timeout 10s \
			-keepalive 2s \
			-queue-size 512 \
			-kcp-window-size 0 \
			-listen "127.0.0.1:${TUNNEL_PORT}" \
			--domain "${TEST_TUNNEL_DOMAIN}" >/dev/null 2>&1 &
		local PID=$!
		# ) &
		;;
	esac

	if wait_for_port $TUNNEL_PORT; then
		if CURL_STATS=$(curl -m "$CURL_TIMEOUT" -4 \
			--socks5 "socks5h://${SOCKS_USER_PASS}@127.0.0.1:$TUNNEL_PORT" \
			-o /dev/null -s \
			-w "total=%{time_total}s | speed_download=%{speed_download}B/s | speed_upload=%{speed_upload}B/s | size_download=%{size_download}B" \
			https://httpbin.org/bytes/10240 2>/dev/null); then
			if ! grep -qw "$RESOLVER" "$RESULTS_FILE"; then
				printf "%-8s | %-15s | %s\n" "${TUNNEL_TYPE}" "$RESOLVER" "$CURL_STATS" >>"$RESULTS_FILE"
			fi
			log_status "✅ ${TUNNEL_TYPE} Working"
		fi
	fi
	kill "$PID" >/dev/null 2>&1

	# # Wait for both background tests to finish before Parallel moves to the next IP
	# wait
}

## Main ##
mkdir -p "$DATA_DIR"
if [[ -s $RESULTS_FILE ]] && grep -qE '^(slip|dnstt|vaydns)' $RESULTS_FILE; then
	NAME_POSTFIX=$(cat "$RESULTS_FILE" | grep "START TIME" | grep -Po '[0-9]{4}[0-9T\-\:]+' | tr -d ':' | tail -n1)
	mv "$RESULTS_FILE" "${RESULTS_FILE}.${NAME_POSTFIX}"
fi

check_dependencies
check_arguments

export -f test_resolver
export -f test_dns_tunnel

# test dns resolvers
set +eu
if ! [ -s "$RESPONSIVE_RESOLVER_FILE" ] || [ -s "$4" ] || ! [ -n "$(find "$RESPONSIVE_RESOLVER_FILE" -mtime -1)" ]; then
	echo "[INFO] Resolver Test (filtering responsive DNS resolvers) | Hostname: $HOSTNAME | DNS_UTILITY: '$DNS_UTILITY' | RESOLVER FILE: ${RESOLVER_FILE}($(wc -l <"$RESOLVER_FILE")) | Parallel Jobs: $((PARALLEL_JOBS * 2)) | TEST RESOLVER DOMAIN: $TEST_RESOLVER_DOMAIN"
	sort -u "$RESOLVER_FILE" | grep -vE '^#|^$' | shuf |
		parallel --bar -j "$((PARALLEL_JOBS * 2))" test_resolver {} "${DNS_COMMAND_OPTIONS[@]}" "${DNS_COMMAND_NS_QUERY[@]}"

	if [[ ! -s "$RESPONSIVE_RESOLVER_FILE" ]]; then
		echo "[INFO] No responsive DNS resolver found. Exit 0"
		exit 0
	fi
	echo "[INFO] Found $(wc -l <"$RESPONSIVE_RESOLVER_FILE") responsive DNS resolvers."
fi
set -eu

# test dns tunnel
echo "[INFO] DNS Tunnel Test | START TIME: $(date +%FT%H:%M:%S) | Hostname: $HOSTNAME | Test TUNNEL TYPE: ${TUNNEL_TYPE} ${VAYDNS_RECORD_TYPE} ${SLIP_PLUS} | Parallel Jobs: $PARALLEL_JOBS | Test Domain: ${TEST_TUNNEL_DOMAIN}" | tee -a "$RESULTS_FILE"
sort -u "$RESPONSIVE_RESOLVER_FILE" | shuf |
	parallel --bar --tag -j "$PARALLEL_JOBS" test_dns_tunnel {} {#}

echo -e "\n[INFO] Test Complete. Total Successes: $(cat $RESULTS_FILE | grep -cv '[INFO]')"
cat "$RESULTS_FILE" | grep -v 'TIME' | grep -i "$TUNNEL_TYPE" | awk -F'|' '{gsub(/ /,"",$0); print $2 " | "$3" | "$4}' | sed -E 's/(total|speed_download)=//g' | sort -n -t'|' -k2
echo "[INFO] TEST END TIME: $(date +%FT%H:%M:%S)" >>"$RESULTS_FILE"

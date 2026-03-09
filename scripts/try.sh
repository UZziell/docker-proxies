#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuration
export JOBS="${1:-20}"
export TEST_MODE="${2}"
export TEST_DOMAIN="${3}"
export DNS_TEST_DOMAIN="${4:-}"
export SLIP_PLUS="${5:-}"
export DNS_FILE="${6:-./dns-ir-extended.txt}"

export SOCKS_USER_PASS=

export DATA_DIR="./data"
export WORKING_DNS_FILE="${DATA_DIR}/dns-working.txt"
export RESULTS_FILE="${DATA_DIR}/RESULTS.txt"
export SLIPSTREAM_PATH="../slipstream-rust/bin"
export DNSTT_PATH="../dnstt"
export TIMEOUT=20
export CURL_TIMEOUT=15
export DNS_REQUEST_TIMEOUT=5

mkdir -p "$DATA_DIR"
if [[ -s $RESULTS_FILE ]] && grep -qE 'Slipstream|DNSTT' $RESULTS_FILE ; then
	NAME_POSTFIX=$(cat "$RESULTS_FILE" | grep "TEST START TIME" | grep -Po '[0-9]{4}[0-9T\-\:]+' | tr -d ':' | tail -n1)
	mv "$RESULTS_FILE" "${RESULTS_FILE}.${NAME_POSTFIX}"
fi

# Dependency Pre-check
if ! command -v parallel >/dev/null 2>&1; then
	echo "[!] GNU Parallel not found. Attempting to install..."
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update && sudo apt-get install -y parallel
	else
		echo "[FATAL] This script requires GNU Parallel. Please install it manually."
		exit 1
	fi
fi

# DNS Utility Selection
for cmd in kdig dig drill dog; do
	if command -v "$cmd" >/dev/null 2>&1; then
		export DNS_UTILITY="$cmd"
		case "$DNS_UTILITY" in
		dig)
			export DNS_COMMAND_OPTIONS="+short +fail"
			export DNS_COMMAND_NS_QUERY="-t NS"
			if [ -z "$DNS_TEST_DOMAIN" ]; then
				DNS_TEST_DOMAIN=$(dig "${DNS_COMMAND_NS_QUERY}" "${DNS_COMMAND_OPTIONS}" "${TEST_DOMAIN}")
			fi
			;;
		dog)
			export DNS_COMMAND_OPTIONS="--short"
			export DNS_COMMAND_NS_QUERY="--type=NS"
			if [ -z "$DNS_TEST_DOMAIN" ]; then
				DNS_TEST_DOMAIN=$(dog "${DNS_COMMAND_NS_QUERY}" "${DNS_COMMAND_OPTIONS}" "${TEST_DOMAIN}")
			fi
			;;
		esac
		break
	fi
done

print_help() {
	echo "Usage:"
	echo "  ./try.sh [JOBS] [MODE=slip/dnstt] [TEST_DOMAIN] [DNS_TEST_DOMAIN(optional)] [SLIP_PLUS(optional)] [DNS_FILE(optional)]"
	echo "Example: "
	echo "  ./try.sh 50 slip t.example.com ns.example.com '-plus' ./dns-custom.txt"
}

# Arguments check
if [ -z "$DNS_UTILITY" ]; then
	echo "[FATAL] No DNS utility found (dig, kdig, drill, or dog). Install 'dnsutils' or 'knot-dnsutils'."
	print_help
	exit 1
elif [[ ! "$TEST_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\.?$ ]]; then
	echo "[FATAL] '${TEST_DOMAIN}' is not a valid test domain."
	print_help
	exit 1
elif [[ ! "$DNS_TEST_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\.?$ ]]; then
	echo "[FATAL] Could not resolve NS record for '${TEST_DOMAIN}'. Try setting it as positonal argument "
	print_help
	exit 1
fi

# DNS Pre-filtering
set +eu
if ! [ -s "$WORKING_DNS_FILE" ] || [ -s "$4" ] || ! [ -n "$(find "$WORKING_DNS_FILE" -mtime -1)" ]; then
	echo "[*] Using '$DNS_UTILITY' for filtering responsive DNS servers | DNS FILE: ${DNS_FILE}($(wc -l < "$DNS_FILE")) | Parallel: $((JOBS * 2)) | DNS TEST DOMAIN: $DNS_TEST_DOMAIN"
	# Filters based on basic response to a known record
	cat "$DNS_FILE" | parallel -j "$((JOBS * 2))" --bar \
		"timeout $DNS_REQUEST_TIMEOUT $DNS_UTILITY $DNS_COMMAND_OPTIONS @{} ${DNS_TEST_DOMAIN} >/dev/null 2>&1 && echo {}" >>"$WORKING_DNS_FILE"
		# "timeout $DNS_REQUEST_TIMEOUT $DNS_UTILITY $DNS_COMMAND_OPTIONS @{} ${DNS_TEST_DOMAIN} 2>/dev/null \| grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null 2>&1 && echo {}" >>"$WORKING_DNS_FILE"
		# "timeout $DNS_REQUEST_TIMEOUT $DNS_UTILITY $DNS_COMMAND_NS_QUERY $DNS_COMMAND_OPTIONS @{} ${TEST_DOMAIN} >/dev/null 2>&1 && echo {}" >>"$WORKING_DNS_FILE"
	echo "[+] Found $(wc -l <"$WORKING_DNS_FILE") responsive DNS servers."
fi
set -eu

# Testing Function
test_resolver() {
	local DNS=$1
	local JOB_ID=$2
	local BASE_PORT=8000

	# helper for logging
	log_status() { echo -e "$1" >&2; }

	# Helper to wait for a port to open
	wait_for_port() {
		local port=$1
		for i in {1..30}; do
			(ss -tlpn | grep -q ":${port}") >/dev/null 2>&1 && return 0
			sleep 0.2
		done
		return 1
	}

	case "$TEST_MODE" in
	slip)
		# Run Slipstream in background
		local PORT_SLIP=$((BASE_PORT + JOB_ID))
		(
			timeout $TIMEOUT "$SLIPSTREAM_PATH/slipstream-client${SLIP_PLUS}" \
				--tcp-listen-port "$PORT_SLIP" \
				--resolver "$DNS" \
				--keep-alive-interval 30 \
				--congestion-control bbr \
				--domain "${TEST_DOMAIN}" >/dev/null 2>&1 &
			local PID=$!
			if wait_for_port $PORT_SLIP; then

				if CURL_STATS=$(curl -m "$CURL_TIMEOUT" -4 \
					--socks5 socks5h://${SOCKS_USER_PASS}@127.0.0.1:$PORT_SLIP \
					-o /dev/null -s \
					-w "total=%{time_total}s | speed_download=%{speed_download}B/s | speed_upload=%{speed_upload}B/s | size_download=%{size_download}B" \
					https://httpbin.org/bytes/10240 2>/dev/null); then
					if ! grep -qw "$DNS" "$RESULTS_FILE"; then
						printf "%-8s | %-15s | %s\n" "Slipstream" "$DNS" "$CURL_STATS" >>"$RESULTS_FILE"
					fi
					log_status "✅ Slipstream Working"
				fi
			fi
			kill $PID >/dev/null 2>&1
		) &
		;;
	dnstt)
		# Run DNSTT in background
		local PORT_TT=$((BASE_PORT + JOB_ID + 1000)) # Use a different offset to avoid collision
		(
			timeout $TIMEOUT "$DNSTT_PATH/bin/dnstt-client-linux-amd64" \
				-udp "$DNS:53" \
				-utls Chrome \
				-pubkey-file "$DNSTT_PATH/data/server.pub" \
				"${TEST_DOMAIN}" "127.0.0.1:$PORT_TT" >/dev/null 2>&1 &
			local PID=$!
			if wait_for_port $PORT_TT; then
				if CURL_STATS=$(curl -m "$CURL_TIMEOUT" -4 \
					--socks5 socks5h://${SOCKS_USER_PASS}@127.0.0.1:$PORT_TT \
					-o /dev/null -s \
					-w "total=%{time_total}s | speed_download=%{speed_download}B/s | speed_upload=%{speed_upload}B/s | size_download=%{size_download}B" \
					https://httpbin.org/bytes/10240 2>/dev/null); then
					if ! grep -qw "$DNS" "$RESULTS_FILE"; then
						printf "%-8s | %-15s | %s\n" "DNSTT" "$DNS" "$CURL_STATS" >>"$RESULTS_FILE"
					fi
					log_status "✅ DNSTT Working"
				fi
			fi
			kill $PID >/dev/null 2>&1
		) &
		;;
	esac

	# Wait for both background tests to finish before Parallel moves to the next IP
	wait
}

export -f test_resolver

# Execution
echo "[*] Starting deep tests using $JOBS parallel threads"
echo "[*] Test mode: $TEST_MODE $SLIP_PLUS | Test Domain: ${TEST_DOMAIN}"
echo "INFO | TEST START TIME: $(date +%FT%H:%M:%S) | DOMAIN: ${TEST_DOMAIN} $SLIP_PLUS" | tee -a "$RESULTS_FILE"

cat "$WORKING_DNS_FILE" | shuf | parallel \
	--bar \
	--tag \
	--line-buffer \
	-j "$JOBS" \
	test_resolver {} {#}

echo -e "\n[*] Testing Complete."
echo "[*] Total Successes: $(cat "$RESULTS_FILE" | grep -cv 'INFO |')"
cat "$RESULTS_FILE" | grep -i "$TEST_MODE" | awk -F'|' '{gsub(/ /,"",$0); print $2 " | "$3" | "$4}' | sed -E 's/(total|speed_download)=//g' | sort -n -t'|' -k2

echo "INFO | TEST END TIME: $(date +%FT%H:%M:%S)" >>"$RESULTS_FILE"

#!/usr/bin/env bash

# Configuration
# Use first argument for parallel jobs, default to 20
export JOBS="${1:-20}"
export TEST_MODE="${2:-dnstt}"
export DNSTT_DOMAIN="${3:-}"
export SLIPSTREAM_DOMAIN="${3:-}"
export DNS_FILE="${4:-./dns-ir-extended.txt}"

export DNSTT_TEST_DOMAIN=
export SLIPSTREAM_TEST_DOMAIN=
export SOCKS_USER_PASS=

export DATA_DIR="./data"
export WORKING_DNS_FILE="./${DATA_DIR}/dns-working.txt"
export RESULTS_FILE="./${DATA_DIR}/RESULTS.txt"
export SLIPSTREAM_PATH="../slipstream-rust"
export DNSTT_PATH="../dnstt"
export TIMEOUT=20
export CURL_TIMEOUT=10

mkdir -p "$DATA_DIR"
if [[ $TEST_MODE == "dnstt" ]]; then
	export DNS_TEST_DOMAIN=$DNSTT_TEST_DOMAIN
	export TEST_DOMAIN=$DNSTT_DOMAIN
elif [[ $TEST_MODE == "slip" ]]; then
	export DNS_TEST_DOMAIN=$SLIPSTREAM_TEST_DOMAIN
	export TEST_DOMAIN=$SLIPSTREAM_DOMAIN
fi

# Dependency Pre-check
if ! command -v parallel >/dev/null 2>&1; then
	echo "[!] GNU Parallel not found. Attempting to install..."
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update && sudo apt-get install -y parallel
	else
		echo "[E] This script requires GNU Parallel. Please install it manually."
		exit 1
	fi
fi

# DNS Utility Selection
for cmd in kdig dig drill dog; do
	if command -v "$cmd" >/dev/null 2>&1; then
		export DNS_UTILITY="$cmd"
		break
	fi
done
if [ -z "$DNS_UTILITY" ]; then
	echo "[E] No DNS utility found (dig, kdig, drill, or dog). Install 'dnsutils' or 'knot-dnsutils'."
	exit 1
fi

# DNS Pre-filtering
if ! [ -s "$WORKING_DNS_FILE" ] || [ -s "$4" ] || ! [ -n "$(find "$WORKING_DNS_FILE" -mtime -1)" ]; then
	echo "[*] Using '$DNS_UTILITY' for pre-filtering responsive DNS servers | DNS TEST DOMAIN: $DNS_TEST_DOMAIN"
	# Filters based on basic response to a known record	
	cat "$DNS_FILE" | parallel -j "${JOBS}" --bar \
		"timeout 2 $DNS_UTILITY @{} ${DNS_TEST_DOMAIN} >/dev/null 2>&1 && echo {}" >>"$WORKING_DNS_FILE"
	echo "[+] Found $(wc -l <"$WORKING_DNS_FILE") responsive DNS servers."
fi

# Testing Function
test_resolver() {
	local DNS=$1
	local JOB_ID=$2
	local BASE_PORT=8000

	# helper for logging
	log_status() { echo -e "$1" >&2; }

	# Helper to wait for a port to open (faster than static sleep)
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
		# 3.1 Run Slipstream in background
		local PORT_SLIP=$((BASE_PORT + JOB_ID))
		(
			timeout $TIMEOUT "$SLIPSTREAM_PATH/slipstream-client" \
				--tcp-listen-port "$PORT_SLIP" --resolver "$DNS" \
				--domain "${SLIPSTREAM_DOMAIN}" --keep-alive-interval 30 >/dev/null 2>&1 &
			local PID=$!
			if wait_for_port $PORT_SLIP; then
				CURL_STATS=$(curl -m "$CURL_TIMEOUT" -4 \
					--socks5 socks5h://${SOCKS_USER_PASS}@127.0.0.1:$PORT_SLIP \
					-o /dev/null -s \
					-w "total=%{time_total}s | speed_download=%{speed_download}B/s speed_upload=%{speed_upload}B/s size_download=%{size_download}B" \
					http://icanhazip.com 2>/dev/null)
				if [ $? -eq 0 ]; then
					printf "%-8s | %-15s | %s\n" "Slipstream" "$DNS" "$CURL_STATS" >>"$RESULTS_FILE"
					log_status "✅ Slipstream Working"
				fi
			fi
			kill $PID >/dev/null 2>&1
		) &
		;;
	dnstt)
		# 3.2 Run DNSTT in background
		local PORT_TT=$((BASE_PORT + JOB_ID + 1000)) # Use a different offset to avoid collision
		(
			timeout $TIMEOUT "$DNSTT_PATH/dnstt-client-linux-amd64" \
				-udp "$DNS:53" -utls Chrome -pubkey-file "$DNSTT_PATH/data/server.pub" \
				"${DNSTT_DOMAIN}" "127.0.0.1:$PORT_TT" >/dev/null 2>&1 &
			local PID=$!
			if wait_for_port $PORT_TT; then
				CURL_STATS=$(curl -m "$CURL_TIMEOUT" -4 \
					--socks5 socks5h://${SOCKS_USER_PASS}@127.0.0.1:$PORT_TT \
					-o /dev/null -s \
					-w "total=%{time_total}s | speed_download=%{speed_download}B/s speed_upload=%{speed_upload}B/s size_download=%{size_download}B" \
					http://icanhazip.com 2>/dev/null)
				if [ $? -eq 0 ]; then
					printf "%-8s | %-15s | %s\n" "DNSTT" "$DNS" "$CURL_STATS" >>"$RESULTS_FILE"
					log_status "✅ DNSTT Working"
				fi
				# if curl -m $CURL_TIMEOUT -4 --socks5 socks5h://${SOCKS_USER_PASS}@127.0.0.1:$PORT_TT http://icanhazip.com >/dev/null 2>&1; then
				# 	echo "DNSTT      | $DNS" >>"$RESULTS_FILE"
				# 	log_status "✅ DNSTT Working"
				# fi
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
echo "[*] Starting deep tests using $JOBS parallel threads..."
echo "[*] Test mode: $TEST_MODE | Test Domain: ${TEST_DOMAIN}"
echo "INFO | TEST START TIME: $(date +%FT%H:%M:%S) | DOMAIN: ${TEST_DOMAIN}" >>"$RESULTS_FILE"

cat "$WORKING_DNS_FILE" | parallel \
	--bar \
	--tag \
	--line-buffer \
	-j "$JOBS" \
	test_resolver {} {#}

echo -e "\n[*] Testing Complete."
echo "[*] Total Successes: $(cat "$RESULTS_FILE" | grep -cv 'INFO |')"
cat "$RESULTS_FILE"

echo "INFO | TEST END TIME: $(date +%FT%H:%M:%S)" >>"$RESULTS_FILE"

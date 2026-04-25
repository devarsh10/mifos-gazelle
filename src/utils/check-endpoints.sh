#!/usr/bin/env bash
# check-endpoints.sh -- Verify all Mifos Gazelle ingress endpoints are reachable
#
# Usage: check-endpoints.sh [-c <config_file>] [-h]
#
# Runs one curl per ingress, hits each service's health path, and reports
# PASS/FAIL. Exits non-zero if any check fails so CircleCI can gate on it.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RESET='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
default_config_ini="$(cd "$SCRIPT_DIR/../../config" && pwd)/config.ini"
config_ini="$default_config_ini"

function usage() {
  cat <<EOF
Usage: $0 [-c <config_file>] [-h]
  -c  Path to config.ini (default: ../../config/config.ini)
  -h  Show this help
EOF
}

while getopts ":c:h" opt; do
  case $opt in
    c) config_ini="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

if [[ ! -f "$config_ini" ]]; then
  echo -e "${RED}Error: Config file not found: $config_ini${RESET}" >&2
  exit 1
fi

GAZELLE_DOMAIN=$(grep GAZELLE_DOMAIN "$config_ini" | cut -d '=' -f2 | tr -d " ")
if [[ -z "$GAZELLE_DOMAIN" ]]; then
  echo -e "${RED}Error: GAZELLE_DOMAIN not set in $config_ini${RESET}" >&2
  exit 1
fi

D="$GAZELLE_DOMAIN"
MIFOS_AUTH="mifos:password"
pass=0
fail=0
failures=()

echo -e "${BLUE}=== Mifos Gazelle Endpoint Health Check ===${RESET}"
echo "Domain: $D"
echo ""

echo -e "${BLUE}--- Active Ingresses (kubectl get ingress -A) ---${RESET}"
kubectl get ingress -A 2>/dev/null || echo "  (kubectl not available or cluster unreachable)"
echo ""

# check_endpoint <name> <expected> <url> [curl_flags...]
#
# <expected> is either an exact HTTP code ("200") or "non5xx"
# (accepts 1xx-4xx, rejects 5xx and 000/connection-error).
check_endpoint() {
  local name="$1"
  local expected="$2"
  local url="$3"
  shift 3
  local curl_args=("$@")

  printf "  %-38s " "$name"

  local http_code
  http_code=$(curl -o /dev/null -w '%{http_code}' \
    --max-time 15 --connect-timeout 5 \
    "${curl_args[@]}" "$url" 2>/dev/null) || http_code="000"

  local ok=false
  if [[ "$expected" == "non5xx" ]]; then
    # 1xx-4xx = service is reachable and responding normally
    [[ "$http_code" =~ ^[1-4][0-9][0-9]$ ]] && ok=true
  elif [[ "$expected" == "reachable" ]]; then
    # any HTTP response (including 5xx) means the ingress and pod are up
    [[ "$http_code" =~ ^[1-5][0-9][0-9]$ ]] && ok=true
  elif [[ "$http_code" == "$expected" ]]; then
    ok=true
  fi

  if $ok; then
    echo -e "[${GREEN}PASS${RESET}] HTTP $http_code"
    pass=$((pass + 1))
  else
    echo -e "[${RED}FAIL${RESET}] HTTP $http_code (expected: $expected)"
    fail=$((fail + 1))
    failures+=("$name  ->  $url")
  fi
}

echo -e "${BLUE}--- Core Services ---${RESET}"

check_endpoint "MifosX Fineract" "200" \
  "https://mifos.${D}/fineract-provider/api/v1/clients?limit=1" \
  -sk -u "$MIFOS_AUTH" -H "Fineract-Platform-TenantId: greenbank"

check_endpoint "Operations Backend" "200" \
  "https://ops-bk.${D}/actuator/health" \
  -sk

# Actuator management port is not exposed via ingress — check the transfer endpoint instead.
# GET on a POST endpoint returns 401/405, both are non5xx.
check_endpoint "Channel Connector" "non5xx" \
  "https://channel.${D}/channel/transfer" \
  -sk

# Ingress only routes /batchtransactions (POST). GET returns 500 from the app (no auth/body).
# Any HTTP response (including 5xx) means the ingress and pod are up.
check_endpoint "Bulk Processor" "reachable" \
  "https://bulk-processor.${D}/batchtransactions" \
  -sk

echo ""
echo -e "${BLUE}--- UI Services ---${RESET}"

check_endpoint "Operations Web" "non5xx" \
  "http://ops.${D}/" \
  -skL

check_endpoint "vNext Admin" "non5xx" \
  "http://vnextadmin.${D}/" \
  -skL

check_endpoint "Zeebe Operate" "200" \
  "http://zeebe-operate.${D}/actuator/health" \
  -s

echo ""
echo -e "${BLUE}--- Infrastructure Services ---${RESET}"

check_endpoint "Elasticsearch" "200" \
  "http://elasticsearch.${D}/_cluster/health" \
  -s

check_endpoint "Kibana" "200" \
  "http://kibana.${D}/api/status" \
  -s

check_endpoint "Redpanda Console" "non5xx" \
  "http://redpanda-console.${D}/" \
  -sL

# Mongo Express requires basic auth — 401 means the service is up.
check_endpoint "Mongo Express" "non5xx" \
  "http://mongoexpress.${D}/" \
  -s

check_endpoint "Minio" "200" \
  "http://minio.${D}/minio/health/live" \
  -s

check_endpoint "Minio Console" "non5xx" \
  "http://minio-console.${D}/" \
  -skL

echo ""
echo -e "${BLUE}===========================================${RESET}"
echo -e "  ${GREEN}PASS: $pass${RESET}   ${RED}FAIL: $fail${RESET}"
echo -e "${BLUE}===========================================${RESET}"

if [[ $fail -gt 0 ]]; then
  echo ""
  echo -e "${RED}Failed endpoints:${RESET}"
  for f in "${failures[@]}"; do
    echo -e "  ${RED}x${RESET} $f"
  done
  echo ""
  echo -e "${RED}Endpoint check failed — skipping further tests.${RESET}"
  exit 1
fi

echo ""
echo -e "${GREEN}All endpoints healthy — safe to proceed.${RESET}"

#!/bin/bash

# Final Connection Script
# Connects the node to the hub after all setup is complete

set +e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
    log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
    error_exit() { log_error "$1"; exit 1; }
    command_exists() { command -v "$1" >/dev/null 2>&1; }
    setup_dns() {
        local a="${1:-8.8.8.8}" b="${2:-1.1.1.1}"
        cat > /etc/resolv.conf <<EOF
options timeout:2 attempts:3 rotate
nameserver $a
nameserver $b
EOF
    }
    print_banner() {
        echo -e "${CYAN}${BOLD}" >&2
        echo "╔══════════════════════════════════════════════════════════╗" >&2
        printf "║ %-56s ║\n" "$1" >&2
        echo "╚══════════════════════════════════════════════════════════╝" >&2
        echo -e "${NC}" >&2
    }
    mask_secret() {
        local v="$1"
        [[ ${#v} -le 8 ]] && echo "****" || echo "${v:0:4}****${v: -4}"
    }
    SHECAN_DNS_PRIMARY="178.22.122.100"
    SHECAN_DNS_SECONDARY="185.51.200.2"
}

if [[ -z "${TOKEN:-}" || -z "${HUB_URL:-}" ]] && [[ -f /.env ]]; then
    # Allow a manual retry after editing the runtime environment file.
    source /.env
fi

if [[ -z "${TOKEN:-}" ]]; then
    error_exit "TOKEN environment variable is not set"
fi

if [[ -z "${HUB_URL:-}" ]]; then
    error_exit "HUB_URL environment variable is not set"
fi
HUB_URL=$(normalize_hub_url "$HUB_URL") || error_exit "Invalid HUB_URL"
export HUB_URL

if [[ "${COUNTRY:-}" == "IR" ]]; then
    log_info "Configuring Shecan DNS for Iranian servers..."
    setup_dns "${SHECAN_DNS_PRIMARY}" "${SHECAN_DNS_SECONDARY}"
fi

log_info "Waiting for node-manager services to become ready..."
if declare -f wait_with_countdown >/dev/null 2>&1; then
    wait_with_countdown 10 "Service warm-up"
else
    sleep 10
fi

if ! command_exists jq; then
    error_exit "jq is required but not installed"
fi

API_URL="http://127.0.0.1:8123/api/v1/connect/"
MAX_RETRIES="${CONNECT_MAX_RETRIES:-8}"
RETRY_DELAY="${CONNECT_RETRY_DELAY:-5}"
attempt=1

TOKEN_MASKED=$(mask_secret "$TOKEN")
log_info "Connecting to hub: ${HUB_URL} (token: ${TOKEN_MASKED})"

extract_error_message() {
    local response="$1"
    local message=""

    message=$(echo "$response" | jq -r '.response.message // empty' 2>/dev/null)
    if [[ -n "$message" ]] && [[ "$message" != "null" ]]; then
        if echo "$response" | jq -e '.response.message | type == "array"' >/dev/null 2>&1; then
            message=$(echo "$response" | jq -r '.response.message[0] // empty' 2>/dev/null)
        fi
    fi

    if [[ -z "$message" ]] || [[ "$message" == "null" ]]; then
        message=$(echo "$response" | jq -r '.message // .error // empty' 2>/dev/null)
    fi

    if [[ -z "$message" ]] || [[ "$message" == "null" ]]; then
        message="Unknown error. Response: ${response:0:200}"
    fi

    echo "$message"
}

# Transient failures worth retrying
is_retryable_failure() {
    local message="$1"
    echo "$message" | grep -Eiq 'timeout|temporar|unavailable|connection refused|try again|not ready|502|503|504'
}

while [[ $attempt -le $MAX_RETRIES ]]; do
    if curl -s --max-time 5 --connect-timeout 3 "http://127.0.0.1:8123" >/dev/null 2>&1; then
        log_info "API is up — connect attempt ${attempt}/${MAX_RETRIES}..."

        # Use JSON for current nodes. Older nodes require query params and return 422.
        response_file=$(mktemp)
        http_code=$(jq -nc '{token: env.TOKEN, hub_url: env.HUB_URL}' | \
            curl -s --max-time 75 --connect-timeout 10 \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            --data-binary @- -o "$response_file" -w '%{http_code}' \
            "$API_URL" 2>/dev/null || echo "000")
        response=$(cat "$response_file")

        if [[ "$http_code" == "422" ]] && echo "$response" | jq -e \
            '[.detail[]? | select(.loc[0] == "query" and .loc[1] == "token")] | length > 0' >/dev/null 2>&1; then
            log_debug "Older node-manager requires query parameters — retrying with encoded values"
            http_code=$(curl -s --max-time 75 --connect-timeout 10 \
                -X POST -G --data-urlencode "token=$TOKEN" --data-urlencode "hub_url=$HUB_URL" \
                -H "Accept: application/json" -o "$response_file" -w '%{http_code}' \
                "$API_URL" 2>/dev/null || echo "000")
            response=$(cat "$response_file")
        fi
        rm -f "$response_file"

        if [[ -z "$response" ]]; then
            log_warn "Empty response from API, retrying in ${RETRY_DELAY}s..."
            ((attempt++))
            sleep "$RETRY_DELAY"
            continue
        fi

        if ! echo "$response" | jq empty 2>/dev/null; then
            log_warn "Invalid JSON response, retrying... (${response:0:100})"
            ((attempt++))
            sleep "$RETRY_DELAY"
            continue
        fi

        success_response=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "error")

        if [[ "$success_response" == "true" ]]; then
            echo "" >&2
            print_banner "Node connected to Chabokan successfully!"
            log_success "Hub: $HUB_URL"
            log_success "Token: $TOKEN_MASKED"
            exit 0
        elif [[ "$success_response" == "false" ]]; then
            message=$(extract_error_message "$response")
            if { [[ "$http_code" == 5* ]] || [[ "$(echo "$response" | jq -r '.status // empty')" == "543" ]] || \
                 is_retryable_failure "$message"; } && [[ $attempt -lt $MAX_RETRIES ]]; then
                log_warn "Connection failed (retryable): $message"
                ((attempt++))
                sleep "$RETRY_DELAY"
                continue
            fi
            log_error "Connection failed: $message"
            log_warn "Full response: $response"
            exit 1
        else
            log_warn "Unexpected response format, retrying... (${response:0:200})"
            ((attempt++))
            sleep "$RETRY_DELAY"
            continue
        fi
    else
        log_warn "API not responding yet (${attempt}/${MAX_RETRIES}), waiting ${RETRY_DELAY}s..."
        ((attempt++))
        sleep "$RETRY_DELAY"
    fi
done

echo "" >&2
log_error "Failed to connect to hub after ${MAX_RETRIES} attempts."
log_error "Checklist:"
log_error "  1. docker compose -f /var/ch-manager/docker-compose.yml ps"
log_error "  2. curl -s http://127.0.0.1:8123  (API must respond)"
log_error "  3. TOKEN and HUB_URL are correct"
log_error "  4. Install log: ${INSTALL_LOG:-/var/log/server-connector-install.log}"
exit 1

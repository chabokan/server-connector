#!/bin/bash

# Common functions and variables for server-connector
# Shared utilities: logging, validation, DNS, retries, and UX helpers

# -----------------------------------------------------------------------------
# Colors (respect NO_COLOR / non-TTY)
# -----------------------------------------------------------------------------
_init_colors() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 2 ]]; then
        RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        NC='\033[0m'
    fi
}
_init_colors

# Avoid breaking when this file is sourced more than once under `set -e`
_COMMON_SH_LOADED=1

# Install log file (optional; set by start.sh)
INSTALL_LOG="${INSTALL_LOG:-/var/log/server-connector-install.log}"

# Shecan DNS (aligned across scripts; safe to re-source)
: "${SHECAN_DNS_PRIMARY:=178.22.122.101}"
: "${SHECAN_DNS_SECONDARY:=185.51.200.1}"

# -----------------------------------------------------------------------------
# Internal log writer
# -----------------------------------------------------------------------------
_log_write() {
    local level="$1"
    local color="$2"
    local message="$3"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "----")
    local line="[${ts}] [${level}] ${message}"
    local colored="${color}[${level}]${NC} ${message}"

    echo -e "${colored}" >&2

    if [[ -n "${INSTALL_LOG:-}" ]]; then
        {
            mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null
            echo "$line" >> "$INSTALL_LOG"
        } 2>/dev/null || true
    fi
}

log_info() {
    _log_write "INFO" "${GREEN}" "$1"
}

log_warn() {
    _log_write "WARN" "${YELLOW}" "$1"
}

log_error() {
    _log_write "ERROR" "${RED}" "$1"
}

log_success() {
    _log_write "OK" "${GREEN}" "$1"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _log_write "DEBUG" "${BLUE}" "$1"
    fi
}

log_step() {
    local current="$1"
    local total="$2"
    local message="$3"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "----")
    local prefix="[${current}/${total}]"
    echo -e "${CYAN}${BOLD}${prefix}${NC} ${message}" >&2
    if [[ -n "${INSTALL_LOG:-}" ]]; then
        {
            mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null
            echo "[${ts}] [STEP] ${prefix} ${message}" >> "$INSTALL_LOG"
        } 2>/dev/null || true
    fi
}

print_banner() {
    local title="$1"
    echo -e "${CYAN}${BOLD}" >&2
    echo "╔══════════════════════════════════════════════════════════╗" >&2
    printf "║ %-56s ║\n" "$title" >&2
    echo "╚══════════════════════════════════════════════════════════╝" >&2
    echo -e "${NC}" >&2
}

print_summary() {
    local server_ip="$1"
    local country="$2"
    local os_name="$3"
    local hub_url="$4"
    local token_masked="$5"

    echo -e "${BOLD}──────── Preflight summary ────────${NC}" >&2
    echo -e "  IP:       ${server_ip}" >&2
    echo -e "  Country:  ${country}" >&2
    echo -e "  OS:       ${os_name}" >&2
    echo -e "  Hub:      ${hub_url}" >&2
    echo -e "  Token:    ${token_masked}" >&2
    echo -e "  Log file: ${INSTALL_LOG}" >&2
    echo -e "${BOLD}───────────────────────────────────${NC}" >&2
}

mask_secret() {
    local value="$1"
    local len=${#value}
    if [[ $len -le 8 ]]; then
        echo "****"
    else
        echo "${value:0:4}****${value: -4}"
    fi
}

# Error handling — always exits
error_exit() {
    log_error "$1"
    if [[ -n "${INSTALL_LOG:-}" ]] && [[ -f "$INSTALL_LOG" ]]; then
        log_error "See install log: $INSTALL_LOG"
    fi
    exit "${2:-1}"
}

# Rich ERR trap helper (source then: trap 'on_error $LINENO' ERR)
on_error() {
    local line="${1:-unknown}"
    local cmd="${BASH_COMMAND:-unknown}"
    log_error "Failed at line ${line}: ${cmd}"
    if [[ -n "${INSTALL_LOG:-}" ]] && [[ -f "$INSTALL_LOG" ]]; then
        log_error "Install log: $INSTALL_LOG"
    fi
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Please use sudo or run as root user."
    fi
}

# Validate input
validate_token() {
    local token="$1"
    if [[ -z "$token" ]]; then
        error_exit "TOKEN cannot be empty"
    fi
    if [[ ${#token} -lt 8 ]]; then
        error_exit "TOKEN is too short (minimum 8 characters)"
    fi
}

normalize_hub_url() {
    local url="$1"
    url="${url#https://}"
    url="${url%/}"
    if [[ ! "$url" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]{1,5})?$ ]]; then
        error_exit "HUB_URL must be an HTTPS hostname or origin without a path"
    fi
    if [[ "$url" == *:* ]]; then
        local port="${url##*:}"
        if (( 10#$port < 1 || 10#$port > 65535 )); then
            error_exit "HUB_URL port must be between 1 and 65535"
        fi
    fi
    printf '%s\n' "$url"
}

validate_url() {
    normalize_hub_url "$1" >/dev/null
}

validate_python() {
    if ! command -v python3 >/dev/null 2>&1 || \
       ! python3 -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] <= (3, 13) else 1)'; then
        error_exit "node-manager requires host Python 3.9 through 3.13 (Ubuntu 20.04 defaults to 3.8)"
    fi
}

# Detect OS
detect_os() {
    local os_release_file=""

    if [[ -f /etc/os-release ]]; then
        os_release_file="/etc/os-release"
    elif [[ -f /usr/lib/os-release ]]; then
        os_release_file="/usr/lib/os-release"
    else
        error_exit "Cannot detect operating system. /etc/os-release and /usr/lib/os-release not found."
    fi

    # shellcheck source=/dev/null
    source "$os_release_file"
    export OS_ID="$ID"
    export OS_VERSION_ID="$VERSION_ID"

    export os_version
    os_version=$(grep -i version_id "$os_release_file" | cut -d '"' -f2 | cut -d '.' -f1)

    log_info "Detected OS: $OS_ID $os_version"
}

# Validate OS version
validate_os() {
    detect_os

    case "$OS_ID" in
        ubuntu)
            if [[ ${os_version} -lt 20 ]]; then
                error_exit "Ubuntu 20.04 or higher is required. Detected: $os_version"
            fi
            ;;
        debian)
            if [[ ${os_version} -lt 11 ]]; then
                error_exit "Debian 11 or higher is required. Detected: $os_version"
            fi
            ;;
        *)
            error_exit "Unsupported operating system: $OS_ID. Supported: Ubuntu 20.04+, Debian 11+"
            ;;
    esac
}

# Get server IP
get_server_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    if [[ -z "$ip" ]]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    fi

    if [[ -z "$ip" ]]; then
        error_exit "Cannot detect server IP address"
    fi

    echo "$ip"
}

# Detect country from IP (soft-fail → UNKNOWN)
detect_country() {
    local server_ip="$1"
    local ip_check_url="https://api.country.is/$server_ip"
    local response
    local country

    log_info "Detecting server country..."

    if ! command_exists curl; then
        log_warn "curl not found, cannot detect country. Assuming non-IR."
        export COUNTRY="UNKNOWN"
        return 0
    fi

    response=$(curl -s --max-time 10 --connect-timeout 5 "$ip_check_url" 2>/dev/null || echo "")

    if [[ -z "$response" ]] || echo "$response" | grep -q "\"error\""; then
        log_warn "Could not detect country from IP. Assuming non-IR."
        export COUNTRY="UNKNOWN"
        return 0
    fi

    # Prefer jq if available; fall back to grep
    if command_exists jq; then
        country=$(echo "$response" | jq -r '.country // empty' 2>/dev/null || echo "")
    else
        country=$(echo "$response" | grep -o -P '"country":"\K[^"]+' 2>/dev/null | tr -d '"' || echo "")
        if [[ -z "$country" ]]; then
            country=$(echo "$response" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        fi
    fi

    if [[ -z "$country" ]]; then
        log_warn "Could not parse country from API response. Assuming non-IR."
        export COUNTRY="UNKNOWN"
    else
        export COUNTRY="$country"
        log_success "Server country detected: $COUNTRY"
    fi
}

# Setup DNS (backs up previous resolv.conf)
setup_dns() {
    local dns_servers=("$@")
    local resolv_conf="${DNS_CONFIG_FILE:-/etc/resolv.conf}"

    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        dns_servers=("8.8.8.8" "1.1.1.1")
    fi

    log_info "Setting up DNS servers: ${dns_servers[*]}"

    if [[ -f "$resolv_conf" ]] && [[ ! -L "$resolv_conf" ]]; then
        cp "$resolv_conf" "${resolv_conf}.backup.$(date +%s)" 2>/dev/null || true
    elif [[ -L "$resolv_conf" ]]; then
        # systemd-resolved symlink — replace with static file after stop
        rm -f "$resolv_conf" || return 1
    fi

    cat > "$resolv_conf" <<EOF || return 1
options timeout:2 attempts:3 rotate
$(for dns in "${dns_servers[@]}"; do echo "nameserver $dns"; done)
EOF

    log_success "DNS configuration updated"
}

# Countdown wait with visible progress
wait_with_countdown() {
    local seconds="${1:-10}"
    local message="${2:-Waiting}"
    local remaining="$seconds"

    log_info "${message} (${seconds}s)..."
    while [[ $remaining -gt 0 ]]; do
        printf "\r${CYAN}[WAIT]${NC} %s — %ds remaining   " "$message" "$remaining" >&2
        sleep 1
        ((remaining--)) || true
    done
    printf "\r${GREEN}[OK]${NC}   %s — done.                    \n" "$message" >&2
}

# Retry function
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local attempt=1
    shift 2

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $*"
        if "$@"; then
            return 0
        fi
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep "$delay"
        fi
        ((attempt++)) || true
    done

    log_error "Command failed after $max_attempts attempts: $*"
    return 1
}

# Safe service restart
restart_service() {
    local service="$1"

    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1 || \
       systemctl status "$service" >/dev/null 2>&1; then
        :
    else
        # May still exist under alternate name
        if ! systemctl cat "$service" >/dev/null 2>&1; then
            log_debug "Service $service not found, skipping restart"
            return 0
        fi
    fi

    log_info "Restarting service: $service"
    if systemctl restart "$service" 2>/dev/null; then
        log_success "Service $service restarted"
        return 0
    fi

    log_warn "systemctl restart failed for $service, trying service command..."
    service "$service" restart 2>/dev/null || log_warn "Failed to restart service $service"
}

# Write a minimal, locked-down env file for cron / node-manager
write_runtime_env() {
    local env_file="${1:-/.env}"

    log_info "Writing runtime environment to $env_file..."
    umask 077
    {
        printf '# Generated by server-connector — do not commit\n'
        printf 'export TOKEN=%q\n' "${TOKEN:-}"
        printf 'export HUB_URL=%q\n' "${HUB_URL:-}"
        printf 'export COUNTRY=%q\n' "${COUNTRY:-}"
        printf 'export OS_ID=%q\n' "${OS_ID:-}"
        printf 'export os_version=%q\n' "${os_version:-}"
    } > "$env_file"
    chmod 600 "$env_file"
    log_success "Runtime environment saved (${env_file}, mode 600)"
}

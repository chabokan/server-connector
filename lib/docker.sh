#!/bin/bash

# Docker Installation Functions
# Provides functions for installing Docker on different distributions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    log_error() { echo "ERROR: $1" >&2; exit 1; }
    log_info() { echo "INFO: $1" >&2; }
    log_warn() { echo "WARN: $1" >&2; }
    log_success() { echo "OK: $1" >&2; }
    log_debug() { :; }
    error_exit() { log_error "$1"; exit "${2:-1}"; }
    restart_service() { systemctl restart "$1" 2>/dev/null || true; }
    retry_command() { shift 2; "$@"; }
    write_runtime_env() {
        cat > /.env <<EOF
export TOKEN='${TOKEN:-}'
export HUB_URL='${HUB_URL:-}'
export COUNTRY='${COUNTRY:-}'
EOF
        chmod 600 /.env
    }
}

# Remove old Docker packages
remove_old_docker() {
    local os_id="$1"
    local os_version="$2"
    local packages=()

    log_info "Removing old Docker packages..."

    case "$os_id" in
        ubuntu)
            if [[ "$os_version" == "22" ]] || [[ "$os_version" == "24" ]]; then
                packages=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
            elif [[ "$os_version" == "20" ]]; then
                packages=(docker.io docker-doc docker-compose docker-compose-v2 containerd runc)
            fi
            ;;
        debian)
            if [[ "$os_version" == "12" ]] || [[ "$os_version" == "13" ]]; then
                packages=(docker.io docker-doc docker-compose podman-docker containerd runc)
            elif [[ "$os_version" == "11" ]]; then
                packages=(docker.io docker-doc docker-compose containerd runc)
            fi
            ;;
    esac

    for pkg in "${packages[@]}"; do
        if dpkg -l 2>/dev/null | grep -q "^ii.*$pkg"; then
            log_info "Removing $pkg..."
            apt-get remove -y "$pkg" >/dev/null 2>&1 || true
        fi
    done
}

# Preferred pinned versions (fallback to latest if unavailable)
_docker_preferred_version() {
    local os_id="$1"
    local os_version="$2"

    case "$os_id" in
        ubuntu)
            case "$os_version" in
                22) echo "5:29.6.1-1~ubuntu.22.04~jammy" ;;
                24) echo "5:29.6.1-1~ubuntu.24.04~noble" ;;
                20) echo "5:29.6.1-1~ubuntu.20.04~focal" ;;
                *) echo "" ;;
            esac
            ;;
        debian)
            case "$os_version" in
                12) echo "5:29.6.1-1~debian.12~bookworm" ;;
                11) echo "5:29.6.1-1~debian.11~bullseye" ;;
                *) echo "" ;;
            esac
            ;;
        *) echo "" ;;
    esac
}

# Install Docker
install_docker() {
    local os_id="$1"
    local os_version="$2"
    local version_string=""
    local apt_log
    apt_log=$(mktemp)

    log_info "Installing Docker for $os_id $os_version..."

    remove_old_docker "$os_id" "$os_version"

    log_info "Updating package lists..."
    apt-get update -qq || error_exit "apt-get update failed before Docker install"

    log_info "Installing Docker prerequisites..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl gnupg >"$apt_log" 2>&1; then
        log_error "Failed to install Docker prerequisites"
        tail -n 40 "$apt_log" >&2 || true
        rm -f "$apt_log"
        error_exit "Docker prerequisite install failed"
    fi

    log_info "Setting up Docker repository..."
    install -m 0755 -d /etc/apt/keyrings

    if [[ "$os_id" == "ubuntu" ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    elif [[ "$os_id" == "debian" ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        rm -f "$apt_log"
        error_exit "Unsupported OS for Docker install: $os_id"
    fi

    apt-get update -qq || error_exit "apt-get update failed after adding Docker repo"

    version_string=$(_docker_preferred_version "$os_id" "$os_version")

    if [[ -n "$version_string" ]] && apt-cache show "docker-ce=${version_string}" >/dev/null 2>&1; then
        log_info "Installing Docker (pinned: $version_string)..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y \
            "docker-ce=${version_string}" \
            "docker-ce-cli=${version_string}" \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin >"$apt_log" 2>&1; then
            log_warn "Pinned Docker version unavailable or failed — falling back to latest..."
            version_string=""
        fi
    else
        if [[ -n "$version_string" ]]; then
            log_warn "Pinned Docker version not in apt cache — using latest stable"
        fi
        version_string=""
    fi

    if [[ -z "$version_string" ]]; then
        log_info "Installing Docker (latest stable)..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin >"$apt_log" 2>&1; then
            log_error "Failed to install Docker packages"
            tail -n 50 "$apt_log" >&2 || true
            rm -f "$apt_log"
            error_exit "Docker package install failed"
        fi
    fi
    rm -f "$apt_log"

    apt-mark hold docker-ce docker-ce-cli 2>/dev/null || true

    if dpkg -l 2>/dev/null | grep -q "^ii.*postfix"; then
        log_info "Removing postfix..."
        apt-get purge -y postfix >/dev/null 2>&1 || true
    fi

    log_info "Enabling and starting Docker..."
    systemctl enable docker >/dev/null 2>&1 || true
    restart_service docker || systemctl start docker || true

    if docker --version >/dev/null 2>&1; then
        log_success "Docker installed: $(docker --version)"
    else
        error_exit "Docker installation verification failed"
    fi
}

# Setup node-manager
setup_node_manager() {
    local os_id="$1"
    local os_version="$2"
    local node_manager_repo="${NODE_MANAGER_REPO:-https://github.com/chabokan/node-manager}"
    local use_venv=true
    local pip_log
    pip_log=$(mktemp)

    log_info "Setting up node-manager..."

    if [[ -d /var/ch-manager ]]; then
        log_info "Removing existing node-manager installation..."
        rm -rf /var/ch-manager
    fi

    log_info "Cloning node-manager repository..."
    if ! git clone --depth 1 "$node_manager_repo" /var/ch-manager; then
        rm -f "$pip_log"
        error_exit "Failed to clone node-manager repository"
    fi

    cd /var/ch-manager/ || error_exit "Failed to change to node-manager directory"

    if [[ "$os_id" == "ubuntu" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv venv || error_exit "Failed to create virtual environment"

        log_info "Installing Python dependencies into venv..."
        venv/bin/pip install --upgrade pip >"$pip_log" 2>&1 || true
        if ! retry_command 3 5 venv/bin/pip install -r requirements.txt; then
            log_error "pip install failed. Last output:"
            tail -n 40 "$pip_log" >&2 || true
            # Retry once showing output
            if ! venv/bin/pip install -r requirements.txt; then
                rm -f "$pip_log"
                error_exit "Failed to install Python dependencies"
            fi
        fi
    elif [[ "$os_id" == "debian" ]]; then
        use_venv=false
        if [[ "$os_version" -ge 12 ]]; then
            log_info "Installing Python dependencies (system / break-system-packages)..."
            if ! retry_command 3 5 pip3 install --break-system-packages -r requirements.txt; then
                pip3 install --break-system-packages -r requirements.txt || {
                    rm -f "$pip_log"
                    error_exit "Failed to install Python dependencies"
                }
            fi
        else
            log_info "Installing Python dependencies (Debian ${os_version})..."
            if ! retry_command 3 5 pip3 install -r requirements.txt; then
                pip3 install -r requirements.txt || {
                    rm -f "$pip_log"
                    error_exit "Failed to install Python dependencies"
                }
            fi
        fi
    fi
    rm -f "$pip_log"

    if [[ "${COUNTRY:-}" == "IR" ]]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY || true
    fi

    if [[ ! -f "/var/ch-manager/sql_app.db" ]]; then
        log_info "Initializing database (alembic)..."
        if [[ "$use_venv" == "true" ]] && [[ -f venv/bin/activate ]]; then
            # shellcheck source=/dev/null
            source venv/bin/activate
            alembic upgrade head || error_exit "Failed to initialize database"
            deactivate 2>/dev/null || true
        else
            alembic upgrade head || error_exit "Failed to initialize database"
        fi
        log_success "Database initialized"
    fi

    log_info "Starting Docker Compose services..."
    docker compose down >/dev/null 2>&1 || true
    docker compose up -d || error_exit "Failed to start Docker Compose services"
    log_success "Docker Compose services started"

    if declare -f write_runtime_env >/dev/null 2>&1; then
        write_runtime_env "/.env"
    else
        log_warn "write_runtime_env unavailable — writing minimal /.env"
        umask 077
        cat > /.env <<EOF
export TOKEN='${TOKEN:-}'
export HUB_URL='${HUB_URL:-}'
export COUNTRY='${COUNTRY:-}'
EOF
        chmod 600 /.env
    fi

    log_success "Node-manager setup completed"
}

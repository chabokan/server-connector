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

# Update code without removing the repository-local SQLite database or settings.
prepare_node_manager_checkout() {
    local repository="$1"
    local directory="$2"

    if [[ -e "$directory" ]]; then
        if [[ ! -d "$directory/.git" ]]; then
            error_exit "$directory exists but is not a git checkout; refusing to remove server data"
        fi
        log_info "Updating existing node-manager checkout without removing its database..."
        git -C "$directory" pull --ff-only || \
            error_exit "Node-manager checkout has local changes or update failed"
    else
        log_info "Cloning node-manager repository..."
        git clone --depth 1 "$repository" "$directory" || \
            error_exit "Failed to clone node-manager repository"
    fi
}

# Setup node-manager
setup_node_manager() {
    local os_id="$1"
    local os_version="$2"
    local node_manager_repo="${NODE_MANAGER_REPO:-https://github.com/chabokan/node-manager}"
    local pip_log
    local venv_backup=""
    local current_python=""
    local target_python

    log_info "Setting up node-manager..."
    exec 8>/var/lock/chabokan-server-queue.lock
    flock 8 || error_exit "Failed to lock the host job worker during installation"

    if [[ -f /var/ch-manager/docker-compose.yml ]]; then
        # Keep the running checkout intact if the replacement image is unavailable.
        docker compose -f /var/ch-manager/docker-compose.yml pull web || \
            error_exit "Failed to pull node-manager image before updating code"
    fi
    prepare_node_manager_checkout "$node_manager_repo" /var/ch-manager
    pip_log=$(mktemp)

    cd /var/ch-manager/ || error_exit "Failed to change to node-manager directory"

    target_python=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
    if [[ -x venv/bin/python ]]; then
        current_python=$(venv/bin/python -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)
    fi
    if [[ -d venv ]] && [[ "$current_python" != "$target_python" ]]; then
        venv_backup="venv.backup.$(date +%s).$$"
        log_info "Host Python changed from ${current_python:-unknown} to $target_python; rebuilding venv..."
        mv venv "$venv_backup" || error_exit "Failed to preserve old virtual environment"
    fi
    if [[ ! -d venv ]]; then
        python3 -m venv venv || {
            [[ -n "$venv_backup" ]] && mv "$venv_backup" venv
            error_exit "Failed to create virtual environment"
        }
    fi
    venv/bin/python -m pip install --upgrade pip >"$pip_log" 2>&1 || true
    if ! retry_command 3 5 venv/bin/python -m pip install -r requirements.txt; then
        if [[ -n "$venv_backup" ]]; then
            rm -rf venv
            mv "$venv_backup" venv
        fi
        rm -f "$pip_log"
        error_exit "Failed to install Python dependencies in the virtual environment"
    fi
    rm -f "$pip_log"

    if [[ "${COUNTRY:-}" == "IR" ]]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY || true
    fi

    log_info "Applying database migrations while preserving existing data..."
    venv/bin/python -m alembic upgrade head || error_exit "Failed to migrate node-manager database"

    log_info "Ensuring Docker registry auth file exists..."
    install -d -m 0700 /root/.docker
    [[ -f /root/.docker/config.json ]] || printf '{}' > /root/.docker/config.json

    log_info "Starting Docker Compose services..."
    docker compose pull web || error_exit "Failed to pull node-manager image"
    docker compose up -d --force-recreate web || error_exit "Failed to start Docker Compose services"
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

    if [[ -n "$venv_backup" ]]; then
        rm -rf "$venv_backup"
    fi
    flock -u 8
    exec 8>&-

    log_success "Node-manager setup completed"
}

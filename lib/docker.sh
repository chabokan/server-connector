#!/bin/bash

# Docker Installation Functions
# Provides functions for installing Docker on different distributions

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh" 2>/dev/null || {
    log_error() { echo "ERROR: $1"; exit 1; }
    log_info() { echo "INFO: $1"; }
    log_warn() { echo "WARN: $1"; }
    error_exit() { log_error "$1"; exit "${2:-1}"; }
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
            if [[ "$os_version" == "12" ]]; then
                packages=(docker.io docker-doc docker-compose podman-docker containerd runc)
            elif [[ "$os_version" == "11" ]]; then
                packages=(docker.io docker-doc docker-compose containerd runc)
            fi
            ;;
    esac
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            log_info "Removing $pkg..."
            apt-get remove -y "$pkg" >/dev/null 2>&1 || true
        fi
    done
}

# Install Docker
install_docker() {
    local os_id="$1"
    local os_version="$2"
    local version_string=""
    
    log_info "Installing Docker for $os_id $os_version..."
    
    # Remove old Docker
    remove_old_docker "$os_id" "$os_version"
    
    # Update package lists
    log_info "Updating package lists..."
    apt-get update -qq
    
    # Install prerequisites
    log_info "Installing Docker prerequisites..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        gnupg >/dev/null 2>&1
    
    # Setup Docker repository
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
    fi
    
    apt-get update -qq
    
    # Determine Docker version string
    case "$os_id" in
        ubuntu)
            case "$os_version" in
                22) version_string="5:26.1.4-1~ubuntu.22.04~jammy" ;;
                24) version_string="5:26.1.4-1~ubuntu.24.04~noble" ;;
                20) version_string="5:26.1.4-1~ubuntu.20.04~focal" ;;
                *) error_exit "Unsupported Ubuntu version: $os_version" ;;
            esac
            ;;
        debian)
            case "$os_version" in
                12) version_string="5:25.0.3-1~debian.12~bookworm" ;;
                11) version_string="5:25.0.3-1~debian.11~bullseye" ;;
                *) error_exit "Unsupported Debian version: $os_version" ;;
            esac
            ;;
        *) error_exit "Unsupported OS: $os_id" ;;
    esac
    
    # Install Docker
    log_info "Installing Docker $version_string..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce="$version_string" \
        docker-ce-cli="$version_string" \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin || {
        error_exit "Failed to install Docker packages"
    }
    
    # Hold Docker packages to prevent automatic updates
    apt-mark hold docker-ce docker-ce-cli
    
    # Remove postfix (if present)
    if dpkg -l | grep -q "^ii.*postfix"; then
        log_info "Removing postfix..."
        apt-get purge -y postfix >/dev/null 2>&1 || true
    fi
    
    # Start Docker service
    log_info "Starting Docker service..."
    restart_service docker || systemctl enable docker || true
    
    # Verify Docker installation
    if docker --version >/dev/null 2>&1; then
        log_info "Docker installed successfully: $(docker --version)"
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
    
    log_info "Setting up node-manager..."
    
    # Remove existing installation
    if [[ -d /var/ch-manager ]]; then
        log_info "Removing existing node-manager installation..."
        rm -rf /var/ch-manager
    fi
    
    # Clone repository
    log_info "Cloning node-manager repository..."
    if ! git clone "$node_manager_repo" /var/ch-manager 2>/dev/null; then
        error_exit "Failed to clone node-manager repository"
    fi
    
    cd /var/ch-manager/ || error_exit "Failed to change to node-manager directory"
    
    # Setup Python environment
    if [[ "$os_id" == "ubuntu" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv venv || error_exit "Failed to create virtual environment"
        
        log_info "Installing Python dependencies..."
        venv/bin/pip install --upgrade pip >/dev/null 2>&1 || true
        retry_command 3 5 venv/bin/pip install -r requirements.txt || {
            log_warn "First pip install had issues, retrying..."
            sleep 2
            retry_command 3 5 venv/bin/pip install -r requirements.txt || {
                error_exit "Failed to install Python dependencies"
            }
        }
    elif [[ "$os_id" == "debian" ]]; then
        if [[ "$os_version" == "12" ]]; then
            log_info "Installing Python dependencies (Debian 12 - system packages)..."
            retry_command 3 5 pip3 install --break-system-packages -r requirements.txt || {
                log_warn "First pip install had issues, retrying..."
                sleep 2
                retry_command 3 5 pip3 install --break-system-packages -r requirements.txt || {
                    error_exit "Failed to install Python dependencies"
                }
            }
            use_venv=false
        else
            log_info "Installing Python dependencies (Debian 11)..."
            retry_command 3 5 pip3 install -r requirements.txt || {
                log_warn "First pip install had issues, retrying..."
                sleep 2
                retry_command 3 5 pip3 install -r requirements.txt || {
                    error_exit "Failed to install Python dependencies"
                }
            }
            use_venv=false
        fi
    fi
    
    # Unset proxy for Iranian servers
    if [[ "${COUNTRY:-}" == "IR" ]]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    fi
    
    # Initialize database if needed
    if [[ ! -f "/var/ch-manager/sql_app.db" ]]; then
        log_info "Initializing database..."
        if [[ "$use_venv" == "true" ]] && [[ -f venv/bin/activate ]]; then
            source venv/bin/activate
            alembic upgrade head || error_exit "Failed to initialize database"
            deactivate
        else
            alembic upgrade head || error_exit "Failed to initialize database"
        fi
    fi
    
    # Start Docker Compose services
    log_info "Starting Docker Compose services..."
    docker compose down >/dev/null 2>&1 || true
    docker compose up -d || error_exit "Failed to start Docker Compose services"
    
    # Export environment variables
    log_info "Exporting environment variables..."
    declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /.env || {
        log_warn "Failed to export environment variables to /.env"
    }
    
    log_info "Node-manager setup completed successfully"
}


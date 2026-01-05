#!/bin/bash

# Final Connection Script
# Connects the node to the hub after all setup is complete

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    error_exit() { log_error "$1"; exit 1; }
    command_exists() { command -v "$1" >/dev/null 2>&1; }
}

# Check required variables
if [[ -z "${TOKEN:-}" ]]; then
    error_exit "TOKEN environment variable is not set"
fi

if [[ -z "${HUB_URL:-}" ]]; then
    error_exit "HUB_URL environment variable is not set"
fi

# Setup DNS for Iran if needed
if [[ "${COUNTRY:-}" == "IR" ]]; then
    log_info "Configuring Shecan DNS for Iranian servers..."
    setup_dns "178.22.122.100" "185.51.200.2"
fi

# Wait for services to be ready
log_info "Waiting for services to be ready..."
sleep 10

# Check if jq is available
if ! command_exists jq; then
    error_exit "jq is required but not installed. Please install jq first."
fi

# Check if node-manager API is accessible
API_URL="http://127.0.0.1:8123/api/v1/connect/"
MAX_RETRIES=6
RETRY_DELAY=5
attempt=1

log_info "Attempting to connect to hub: $HUB_URL"

while [[ $attempt -le $MAX_RETRIES ]]; do
    # Check if API is responding
    if curl -s --max-time 5 --connect-timeout 3 "http://127.0.0.1:8123" >/dev/null 2>&1; then
        log_info "API is responding, attempting connection (attempt $attempt/$MAX_RETRIES)..."
        
        # Build URL with parameters
        url="${API_URL}?token=${TOKEN}&hub_url=${HUB_URL}"
        
        # Make the POST request
        response=$(curl -s --max-time 30 --connect-timeout 10 \
            -X POST \
            -H "Content-Type: application/json" \
            -d "" \
            "$url" 2>/dev/null || echo "")
        
        if [[ -z "$response" ]]; then
            log_warn "Empty response from API, retrying..."
            ((attempt++))
            sleep $RETRY_DELAY
            continue
        fi
        
        # Parse response
        success_response=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "error")
        
        if [[ "$success_response" == "true" ]]; then
            log_info "=========================================="
            log_info "Node connected to chabokan successfully!"
            log_info "=========================================="
            exit 0
        elif [[ "$success_response" == "false" ]]; then
            message_response=$(echo "$response" | jq -r '.response.message' 2>/dev/null || echo "null")
            
            if [[ "$message_response" == "null" ]]; then
                message=$(echo "$response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
                log_error "Connection failed: $message"
            else
                # Handle array or string message
                if echo "$message_response" | jq -e '. | type == "array"' >/dev/null 2>&1; then
                    message=$(echo "$response" | jq -r '.response.message[]' 2>/dev/null | head -1)
                else
                    message="$message_response"
                fi
                log_error "Connection failed: $message"
            fi
            exit 1
        else
            log_warn "Unexpected response format, retrying... (Response: $response)"
            ((attempt++))
            sleep $RETRY_DELAY
            continue
        fi
    else
        log_warn "API not responding yet, waiting ${RETRY_DELAY}s before retry ($attempt/$MAX_RETRIES)..."
        ((attempt++))
        sleep $RETRY_DELAY
    fi
done

log_error "Failed to connect to hub after $MAX_RETRIES attempts. Please check:"
log_error "1. Node-manager service is running (docker compose ps)"
log_error "2. API is accessible on port 8123"
log_error "3. TOKEN and HUB_URL are correct"
exit 1

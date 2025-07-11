#!/bin/bash

# Cricket Monitor Performance Collector Installation Script
# Usage: curl -sSL https://cricketmon.io/install-collector | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
INSTALL_DIR="/opt/cricket-collector"
SERVICE_NAME="cricket-collector"
USER_NAME="cricket"
BINARY_URL_BASE="https://github.com/CricketMonitor/collector/releases/latest/download"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_permissions() {
    # If running as root, that's fine
    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root user"
        return 0
    fi
    
    # If not root, check if we can use sudo
    if ! sudo -n true 2>/dev/null; then
        log_info "This script requires sudo privileges for installation."
        log_info "You may be prompted for your password."
        
        # Test sudo access
        if ! sudo -v; then
            log_error "Unable to obtain sudo privileges. Please ensure you have sudo access."
        fi
    fi
    
    log_info "Permissions verified successfully"
}

# Helper function to run commands with appropriate privileges
run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            ;;
    esac
}

download_binary() {
    local arch=$(detect_architecture)
    local binary_name="cricket-collector-linux-${arch}"
    local download_url="${BINARY_URL_BASE}/${binary_name}"
    
    log_info "Detecting architecture: ${arch}"
    log_info "Downloading collector binary from: ${download_url}"
    
    # Download the binary
    if ! curl -fsSL -o "/tmp/cricket-collector" "$download_url"; then
        log_error "Failed to download binary from: ${download_url}"
        log_info ""
        log_info "Alternative installation options:"
        log_info "1. Check if a release exists at: https://github.com/CricketMonitor/collector/releases"
        log_info "2. Manual build from source:"
        log_info "   git clone https://github.com/CricketMonitor/collector.git"
        log_info "   cd collector/collectors/linux-collector"
        log_info "   go mod tidy && go build -o cricket-collector main.go"
        exit 1
    fi
    
    # Verify the binary is executable
    if ! chmod +x "/tmp/cricket-collector"; then
        log_error "Failed to make binary executable"
        exit 1
    fi
    
    log_success "Binary downloaded successfully"
}

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user: $USER_NAME"
        run_as_root useradd --system --shell /bin/false --home "$INSTALL_DIR" --create-home "$USER_NAME"
        log_success "User created: $USER_NAME"
    else
        log_info "User already exists: $USER_NAME"
    fi
}

install_binary() {
    log_info "Installing binary to $INSTALL_DIR"
    
    run_as_root mkdir -p "$INSTALL_DIR"
    
    # Check if service is running and stop it temporarily for upgrade
    local service_was_running=false
    if run_as_root systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_info "Stopping $SERVICE_NAME service for upgrade..."
        run_as_root systemctl stop "$SERVICE_NAME"
        service_was_running=true
        sleep 2  # Give the process time to fully stop
    fi
    
    # Install the new binary
    run_as_root cp "/tmp/cricket-collector" "$INSTALL_DIR/cricket-collector"
    run_as_root chmod +x "$INSTALL_DIR/cricket-collector"
    run_as_root chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
    
    # Create symlink for global access
    run_as_root ln -sf "$INSTALL_DIR/cricket-collector" "/usr/local/bin/cricket-collector"
    
    # Restart service if it was running
    if [ "$service_was_running" = true ]; then
        log_info "Restarting $SERVICE_NAME service..."
        run_as_root systemctl start "$SERVICE_NAME"
        
        # Verify it started successfully
        if run_as_root systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "Service restarted successfully"
        else
            log_warning "Service may have failed to start. Check: sudo systemctl status $SERVICE_NAME"
        fi
    fi
    
    log_success "Binary installed to $INSTALL_DIR"
}

create_config() {
    local config_file="$INSTALL_DIR/.env"
    
    if [[ ! -f "$config_file" ]]; then
        log_info "Creating configuration file: $config_file"
        
        run_as_root tee "$config_file" > /dev/null <<EOF
# Cricket Monitor Performance Collector Configuration

# API Configuration (REQUIRED)
CRICKET_API_KEY=

# Server Configuration (OPTIONAL - defaults to hostname)
CRICKET_SERVER_NAME=$(hostname)

# Collection Settings
CRICKET_COLLECT_INTERVAL=60

# Debug Mode
CRICKET_DEBUG=false
EOF
        
        run_as_root chown "$USER_NAME:$USER_NAME" "$config_file"
        run_as_root chmod 600 "$config_file"
        
        log_success "Configuration file created: $config_file"
        log_warning "You must set CRICKET_API_KEY in $config_file before starting the service"
    else
        log_info "Configuration file already exists: $config_file"
    fi
}

install_systemd_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    
    log_info "Installing systemd service: $service_file"
    
    run_as_root tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Cricket Monitor Performance Collector
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=$USER_NAME
ExecStart=$INSTALL_DIR/cricket-collector
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env

[Install]
WantedBy=multi-user.target
EOF
    
    run_as_root systemctl daemon-reload
    run_as_root systemctl enable "$SERVICE_NAME"
    
    log_success "Systemd service installed and enabled"
}

show_completion_message() {
    local config_file="$INSTALL_DIR/.env"
    
    echo ""
    
    # Check if this is a fresh install or upgrade
    if [ -f "$config_file" ] && grep -q "CRICKET_API_KEY=" "$config_file" && [ -n "$(grep "CRICKET_API_KEY=" "$config_file" | cut -d'=' -f2)" ]; then
        # Existing installation with API key
        log_success "Cricket Monitor collector has been updated successfully!"
        echo ""
        echo "The collector service has been restarted with the new version."
        echo ""
        echo "You can check the service status with:"
        echo "  sudo systemctl status $SERVICE_NAME"
        echo ""
        echo "View logs with:"
        echo "  sudo journalctl -u $SERVICE_NAME -f"
        echo ""
        echo "Check collector version:"
        echo "  /opt/cricket-collector/cricket-collector --version"
    else
        # Fresh installation
        log_info "The collector is installed but needs an API key to function."
        echo ""
        echo "To complete the setup:"
        echo "1. Visit https://cricketmon.io/dashboard/servers"
        echo "2. Generate your account API key (one key works for all servers)"
        echo "3. Set your API key: sudo nano $INSTALL_DIR/.env"
        echo "4. Update: CRICKET_API_KEY=your_api_key_here"
        echo "5. Start the service: sudo systemctl start $SERVICE_NAME"
        echo ""
        echo "Your server will automatically register when it starts sending metrics!"
        echo ""
        echo "You can check the service status with:"
        echo "  sudo systemctl status $SERVICE_NAME"
        echo ""
        echo "View logs with:"
        echo "  sudo journalctl -u $SERVICE_NAME -f"
        echo ""
    fi
}

cleanup() {
    rm -f "/tmp/cricket-collector"
}

main() {
    echo "=================================================="
    echo "Cricket Monitor Performance Collector Installer"
    echo "=================================================="
    echo ""
    
    check_permissions
    
    log_info "Starting installation..."
    
    download_binary
    create_user
    install_binary
    create_config
    install_systemd_service
    cleanup
    
    log_success "Installation completed successfully!"
    show_completion_message
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
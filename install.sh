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
BINARY_URL_BASE="https://github.com/cricket-monitor/collector/releases/latest/download"

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
    
    # For development/demo, provide instructions instead of trying to download
    log_error "Binary download not yet implemented for development."
    log_info ""
    log_info "To install the Cricket Monitor collector manually:"
    log_info "1. Clone the repository:"
    log_info "   git clone https://github.com/your-org/cricket-monitor.git"
    log_info "2. Build the collector:"
    log_info "   cd cricket-monitor/collectors/linux-collector"
    log_info "   go mod tidy && go build -o cricket-collector main.go"
    log_info "3. Run the manual installation:"
    log_info "   sudo cp cricket-collector /usr/local/bin/"
    log_info "   sudo chmod +x /usr/local/bin/cricket-collector"
    log_info ""
    log_info "For production, this script will download pre-built binaries from GitHub releases."
    exit 1
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
    run_as_root cp "/tmp/cricket-collector" "$INSTALL_DIR/cricket-collector"
    run_as_root chmod +x "$INSTALL_DIR/cricket-collector"
    run_as_root chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
    
    # Create symlink for global access
    run_as_root ln -sf "$INSTALL_DIR/cricket-collector" "/usr/local/bin/cricket-collector"
    
    log_success "Binary installed to $INSTALL_DIR"
}

create_config() {
    local config_file="$INSTALL_DIR/.env"
    
    if [[ ! -f "$config_file" ]]; then
        log_info "Creating configuration file: $config_file"
        
        run_as_root tee "$config_file" > /dev/null <<EOF
# Cricket Monitor Performance Collector Configuration

# API Configuration (REQUIRED)
CRICKET_API_URL=https://collector.cricketmon.io
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

prompt_for_api_key() {
    echo ""
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
    prompt_for_api_key
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
#!/bin/bash

# WireGuard Manager for Arch Linux
# Complete refactor with proper error handling and Arch Linux support
# Usage: ./wg-manager.sh [interface_name]

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/wg-manager-$(date +%Y%m%d).log"
readonly WG_DIR="/etc/wireguard"
readonly BACKUP_DIR="/tmp/wg-manager-backup"

# Default interface (can be overridden by command line)
WG_INTERFACE="${1:-wg0}"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    case "$level" in
        ERROR) echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        INFO)  echo -e "${CYAN}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        *) echo "$message" ;;
    esac
}

# Error handling
error_exit() {
    log ERROR "$1"
    exit "${2:-1}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log WARN "This script requires root privileges. Attempting to re-run with sudo..."
        exec sudo -E bash "$0" "$@"
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Script exited with error code $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Check system requirements
check_requirements() {
    # Check if running on Arch Linux
    if [[ ! -f /etc/arch-release ]]; then
        log WARN "This script is optimized for Arch Linux but will attempt to continue"
    fi
    
    # Check for required commands
    local required_commands=("wg" "wg-quick" "ip" "systemctl" "resolvectl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log ERROR "Missing required commands: ${missing_commands[*]}"
        echo -e "${YELLOW}Install missing packages:${NC}"
        echo "  sudo pacman -S wireguard-tools iproute2 systemd-resolvconf"
        return 1
    fi
    
    # Check if WireGuard module is loaded
    if ! lsmod | grep -q wireguard; then
        log WARN "WireGuard kernel module not loaded, attempting to load..."
        if ! modprobe wireguard; then
            log ERROR "Failed to load WireGuard kernel module"
            echo -e "${YELLOW}Try installing the kernel module:${NC}"
            echo "  sudo pacman -S wireguard-arch"
            return 1
        fi
    fi
    
    return 0
}

# Check if config file exists and is valid
check_config() {
    if [[ ! -f "$WG_CONFIG" ]]; then
        log ERROR "WireGuard config file not found: $WG_CONFIG"
        echo -e "${YELLOW}Available configs:${NC}"
        if ls "$WG_DIR"/*.conf 2>/dev/null; then
            echo -e "${YELLOW}Usage: $SCRIPT_NAME [interface_name]${NC}"
        else
            echo "No WireGuard configurations found in $WG_DIR"
            echo -e "${YELLOW}Create a config file first:${NC}"
            echo "  sudo nano $WG_CONFIG"
        fi
        return 1
    fi
    
    # Basic config validation
    if ! grep -q "\[Interface\]" "$WG_CONFIG" || ! grep -q "\[Peer\]" "$WG_CONFIG"; then
        log ERROR "Invalid WireGuard config format in $WG_CONFIG"
        return 1
    fi
    
    # Check config permissions
    local config_perms=$(stat -c "%a" "$WG_CONFIG")
    if [[ "$config_perms" != "600" ]]; then
        log WARN "Config file permissions are $config_perms, should be 600. Fixing..."
        chmod 600 "$WG_CONFIG"
    fi
    
    return 0
}

# Get VPN connection status
get_vpn_status() {
    if wg show "$WG_INTERFACE" &> /dev/null && ip link show "$WG_INTERFACE" &> /dev/null; then
        echo "CONNECTED"
    else
        echo "DISCONNECTED"
    fi
}

# Get detailed connection info
get_connection_info() {
    if [[ "$(get_vpn_status)" == "DISCONNECTED" ]]; then
        return 1
    fi
    
    local info=""
    
    # Get interface IP
    local interface_ip=$(ip addr show "$WG_INTERFACE" 2>/dev/null | grep -E "inet " | awk '{print $2}' | head -1)
    info+="Interface IP: ${interface_ip:-Unknown}\n"
    
    # Get peer info
    local peer_info=$(wg show "$WG_INTERFACE" 2>/dev/null)
    if [[ -n "$peer_info" ]]; then
        local endpoint=$(echo "$peer_info" | grep "endpoint:" | awk '{print $2}')
        local latest_handshake=$(echo "$peer_info" | grep "latest handshake:" | cut -d: -f2- | xargs)
        local transfer=$(echo "$peer_info" | grep "transfer:" | cut -d: -f2- | xargs)
        
        info+="Endpoint: ${endpoint:-Unknown}\n"
        info+="Latest Handshake: ${latest_handshake:-Never}\n"
        info+="Transfer: ${transfer:-0 B received, 0 B sent}\n"
    fi
    
    echo -e "$info"
}

# Check DNS resolution
check_dns() {
    local test_domains=("google.com" "cloudflare.com" "1.1.1.1")
    
    for domain in "${test_domains[@]}"; do
        if timeout 5 nslookup "$domain" &> /dev/null; then
            return 0
        fi
    done
    return 1
}

# Test internet connectivity
test_connectivity() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    
    for host in "${test_hosts[@]}"; do
        if timeout 5 ping -c 2 "$host" &> /dev/null; then
            return 0
        fi
    done
    return 1
}

# Get external IP
get_external_ip() {
    local ip_services=("https://ipinfo.io/ip" "https://api.ipify.org" "https://icanhazip.com")
    
    for service in "${ip_services[@]}"; do
        local external_ip=$(timeout 10 curl -s "$service" 2>/dev/null | tr -d '\n\r ')
        if [[ -n "$external_ip" && "$external_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$external_ip"
            return 0
        fi
    done
    return 1
}

# Create backup of network state
create_backup() {
    mkdir -p "$BACKUP_DIR"
    
    # Backup current routes
    ip route show > "$BACKUP_DIR/routes_$(date +%s).txt"
    
    # Backup current DNS settings
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf_$(date +%s).backup"
    fi
    
    log INFO "Network state backed up to $BACKUP_DIR"
}

# Connect to VPN
connect_vpn() {
    log INFO "Connecting to WireGuard VPN interface: $WG_INTERFACE"
    
    if [[ "$(get_vpn_status)" == "CONNECTED" ]]; then
        log WARN "WireGuard interface $WG_INTERFACE is already connected"
        return 0
    fi
    
    # Create backup before connecting
    create_backup
    
    # Ensure any existing interface is down
    if ip link show "$WG_INTERFACE" &> /dev/null; then
        log INFO "Cleaning up existing interface..."
        wg-quick down "$WG_INTERFACE" &> /dev/null || true
    fi
    
    # Connect using wg-quick
    if wg-quick up "$WG_INTERFACE"; then
        log SUCCESS "Successfully connected to WireGuard VPN"
        
        # Wait for interface to be fully up
        sleep 3
        
        # Verify connection
        if [[ "$(get_vpn_status)" == "CONNECTED" ]]; then
            # Test connectivity
            if test_connectivity; then
                log SUCCESS "VPN connection verified - internet connectivity working"
            else
                log WARN "VPN connected but internet connectivity test failed"
            fi
            
            # Show connection info
            echo -e "\n${BOLD}Connection Information:${NC}"
            get_connection_info
            
            return 0
        else
            log ERROR "VPN connection failed - interface not active"
            return 1
        fi
    else
        log ERROR "Failed to connect to WireGuard VPN"
        return 1
    fi
}

# Disconnect from VPN
disconnect_vpn() {
    log INFO "Disconnecting from WireGuard VPN interface: $WG_INTERFACE"
    
    if [[ "$(get_vpn_status)" == "DISCONNECTED" ]]; then
        log WARN "WireGuard interface $WG_INTERFACE is already disconnected"
        return 0
    fi
    
    if wg-quick down "$WG_INTERFACE"; then
        log SUCCESS "Successfully disconnected from WireGuard VPN"
        
        # Verify disconnection
        sleep 2
        if [[ "$(get_vpn_status)" == "DISCONNECTED" ]]; then
            log SUCCESS "VPN disconnection verified"
        else
            log WARN "VPN may not be fully disconnected"
        fi
        
        # Restart systemd-resolved to ensure DNS cleanup
        if systemctl is-active systemd-resolved &> /dev/null; then
            systemctl restart systemd-resolved
            log INFO "DNS resolver restarted"
        fi
        
        return 0
    else
        log ERROR "Failed to disconnect from WireGuard VPN"
        return 1
    fi
}

# Restart VPN connection
restart_vpn() {
    log INFO "Restarting WireGuard VPN interface: $WG_INTERFACE"
    
    disconnect_vpn
    sleep 2
    connect_vpn
}

# Enable auto-start on boot
enable_autostart() {
    local service_name="wg-quick@$WG_INTERFACE.service"
    
    if systemctl is-enabled "$service_name" &> /dev/null; then
        log WARN "Auto-start is already enabled for $WG_INTERFACE"
        return 0
    fi
    
    if systemctl enable "$service_name"; then
        log SUCCESS "Auto-start enabled for $WG_INTERFACE"
        echo -e "${GREEN}VPN will automatically connect on boot${NC}"
        return 0
    else
        log ERROR "Failed to enable auto-start for $WG_INTERFACE"
        return 1
    fi
}

# Disable auto-start on boot
disable_autostart() {
    local service_name="wg-quick@$WG_INTERFACE.service"
    
    if ! systemctl is-enabled "$service_name" &> /dev/null; then
        log WARN "Auto-start is already disabled for $WG_INTERFACE"
        return 0
    fi
    
    if systemctl disable "$service_name"; then
        log SUCCESS "Auto-start disabled for $WG_INTERFACE"
        echo -e "${YELLOW}VPN will not automatically connect on boot${NC}"
        return 0
    else
        log ERROR "Failed to disable auto-start for $WG_INTERFACE"
        return 1
    fi
}

# Show detailed status
show_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${CYAN}WireGuard VPN Status - $WG_INTERFACE${BLUE}                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    local status=$(get_vpn_status)
    local service_name="wg-quick@$WG_INTERFACE.service"
    
    # Connection status
    if [[ "$status" == "CONNECTED" ]]; then
        echo -e "${GREEN}● Status: CONNECTED${NC}"
        echo
        get_connection_info
    else
        echo -e "${RED}● Status: DISCONNECTED${NC}"
        echo
    fi
    
    # Auto-start status
    echo -e "${BOLD}Auto-start Status:${NC}"
    if systemctl is-enabled "$service_name" &> /dev/null; then
        echo -e "${GREEN}● Enabled${NC} - VPN will start automatically on boot"
    else
        echo -e "${YELLOW}● Disabled${NC} - VPN will not start automatically on boot"
    fi
    echo
    
    # Network tests (only if connected)
    if [[ "$status" == "CONNECTED" ]]; then
        echo -e "${BOLD}Network Tests:${NC}"
        
        echo -n "DNS Resolution: "
        if check_dns; then
            echo -e "${GREEN}✓ Working${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
        
        echo -n "Internet Connectivity: "
        if test_connectivity; then
            echo -e "${GREEN}✓ Working${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
        
        echo -n "External IP: "
        local external_ip=$(get_external_ip)
        if [[ -n "$external_ip" ]]; then
            echo -e "${GREEN}$external_ip${NC}"
        else
            echo -e "${RED}Unable to determine${NC}"
        fi
        echo
    fi
    
    # Configuration file info
    echo -e "${BOLD}Configuration:${NC}"
    echo "Config file: $WG_CONFIG"
    if [[ -f "$WG_CONFIG" ]]; then
        echo -e "${GREEN}✓ Configuration file exists${NC}"
        local config_size=$(stat -c%s "$WG_CONFIG")
        echo "File size: $config_size bytes"
        local config_perms=$(stat -c "%a" "$WG_CONFIG")
        echo "Permissions: $config_perms"
    else
        echo -e "${RED}✗ Configuration file not found${NC}"
    fi
}

# Interactive menu
show_menu() {
    local status=$(get_vpn_status)
    local status_indicator
    
    if [[ "$status" == "CONNECTED" ]]; then
        status_indicator="${GREEN}● CONNECTED${NC}"
    else
        status_indicator="${RED}● DISCONNECTED${NC}"
    fi
    
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${CYAN}WireGuard VPN Manager${BLUE}                           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BOLD}Interface:${NC} $WG_INTERFACE"
    echo -e "${BOLD}Status:${NC} $status_indicator"
    echo
    echo -e "${CYAN}Available Actions:${NC}"
    echo
    echo -e "${GREEN} 1)${NC} Connect to VPN"
    echo -e "${RED} 2)${NC} Disconnect from VPN"
    echo -e "${YELLOW} 3)${NC} Restart VPN Connection"
    echo -e "${BLUE} 4)${NC} Show Detailed Status"
    echo -e "${PURPLE} 5)${NC} Enable Auto-start on Boot"
    echo -e "${PURPLE} 6)${NC} Disable Auto-start on Boot"
    echo -e "${CYAN} 7)${NC} View Logs"
    echo -e "${RED} 8)${NC} Exit"
    echo
}

# View logs
view_logs() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${CYAN}WireGuard Manager Logs${BLUE}                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "${YELLOW}Recent logs from: $LOG_FILE${NC}"
        echo
        tail -30 "$LOG_FILE"
    else
        echo -e "${YELLOW}No logs found${NC}"
    fi
    echo
    read -p "Press Enter to continue..."
}

# Main function
main() {
    # Handle command line arguments
    case "${1:-}" in
        status)
            show_status
            exit 0
            ;;
        connect)
            check_root "$@"
            check_requirements || error_exit "Requirements check failed"
            check_config || error_exit "Configuration check failed"
            connect_vpn
            exit $?
            ;;
        disconnect)
            check_root "$@"
            check_requirements || error_exit "Requirements check failed"
            disconnect_vpn
            exit $?
            ;;
        restart)
            check_root "$@"
            check_requirements || error_exit "Requirements check failed"
            check_config || error_exit "Configuration check failed"
            restart_vpn
            exit $?
            ;;
        enable-autostart)
            check_root "$@"
            check_requirements || error_exit "Requirements check failed"
            enable_autostart
            exit $?
            ;;
        disable-autostart)
            check_root "$@"
            check_requirements || error_exit "Requirements check failed"
            disable_autostart
            exit $?
            ;;
        help|--help|-h)
            echo "Usage: $SCRIPT_NAME [interface] [command]"
            echo
            echo "Commands:"
            echo "  status              Show VPN status"
            echo "  connect             Connect to VPN"
            echo "  disconnect          Disconnect from VPN"
            echo "  restart             Restart VPN connection"
            echo "  enable-autostart    Enable auto-start on boot"
            echo "  disable-autostart   Disable auto-start on boot"
            echo "  help                Show this help"
            echo
            echo "If no command is specified, interactive menu will be shown."
            echo "Default interface: wg0"
            exit 0
            ;;
    esac
    
    # Check if we need root for interactive mode
    check_root "$@"
    
    # Check requirements
    check_requirements || error_exit "Requirements check failed"
    
    # Check configuration
    check_config || error_exit "Configuration check failed"
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Enter your choice (1-8): " choice
        
        case $choice in
            1)
                connect_vpn
                read -p "Press Enter to continue..."
                ;;
            2)
                disconnect_vpn
                read -p "Press Enter to continue..."
                ;;
            3)
                restart_vpn
                read -p "Press Enter to continue..."
                ;;
            4)
                show_status
                read -p "Press Enter to continue..."
                ;;
            5)
                enable_autostart
                read -p "Press Enter to continue..."
                ;;
            6)
                disable_autostart
                read -p "Press Enter to continue..."
                ;;
            7)
                view_logs
                ;;
            8)
                echo -e "${GREEN}Thank you for using WireGuard Manager!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 1 and 8.${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Run the script
main "$@"

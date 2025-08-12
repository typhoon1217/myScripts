#!/bin/bash

# VPN Network Diagnostic & Fix Tool
# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              VPN Network Diagnostic Tool                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Function to check VPN interface status
check_vpn_interface() {
    echo -e "${CYAN}=== VPN Interface Status ===${NC}"
    
    # Check for common VPN interfaces
    vpn_interfaces=$(ip link show | grep -E "(wg|tun|tap)" | cut -d: -f2 | tr -d ' ')
    
    if [ -z "$vpn_interfaces" ]; then
        echo -e "${RED}❌ No VPN interfaces found (wg*, tun*, tap*)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ VPN Interfaces found:${NC}"
        for iface in $vpn_interfaces; do
            echo "  - $iface"
            ip addr show $iface 2>/dev/null | grep "inet " | awk '{print "    IP: " $2}'
        done
    fi
    echo
}

# Function to check routing table
check_routing() {
    echo -e "${CYAN}=== Routing Table Analysis ===${NC}"
    
    echo -e "${YELLOW}Default Route:${NC}"
    default_route=$(ip route show default | head -1)
    echo "  $default_route"
    
    # Check if default route goes through VPN
    if echo "$default_route" | grep -qE "(wg|tun|tap)"; then
        echo -e "${GREEN}✓ Default route goes through VPN interface${NC}"
    else
        echo -e "${RED}❌ Default route NOT going through VPN (using local network)${NC}"
        echo -e "${YELLOW}This is likely the problem!${NC}"
    fi
    
    echo
    echo -e "${YELLOW}All Routes:${NC}"
    ip route show | head -10
    echo
}

# Function to check DNS settings
check_dns() {
    echo -e "${CYAN}=== DNS Configuration ===${NC}"
    
    echo -e "${YELLOW}Current DNS servers (/etc/resolv.conf):${NC}"
    if [ -f /etc/resolv.conf ]; then
        grep "nameserver" /etc/resolv.conf | head -5
        
        # Check if using local/ISP DNS
        local_dns=$(grep "nameserver" /etc/resolv.conf | grep -E "(192\.168\.|10\.|172\.|127\.)")
        if [ -n "$local_dns" ]; then
            echo -e "${RED}❌ Using local network DNS - DNS leaks possible${NC}"
            echo "$local_dns"
        else
            echo -e "${GREEN}✓ Using external DNS servers${NC}"
        fi
    else
        echo -e "${RED}❌ /etc/resolv.conf not found${NC}"
    fi
    echo
}

# Function to test connectivity
test_connectivity() {
    echo -e "${CYAN}=== Connectivity Tests ===${NC}"
    
    echo -e "${YELLOW}Testing external IP...${NC}"
    external_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null)
    if [ -n "$external_ip" ]; then
        echo "  External IP: $external_ip"
        
        # Check if IP is in local network range
        if echo "$external_ip" | grep -qE "^(192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)|^127\."; then
            echo -e "${RED}❌ External IP shows local network - VPN not working${NC}"
        else
            echo -e "${GREEN}✓ External IP shows VPN server${NC}"
        fi
    else
        echo -e "${RED}❌ Cannot get external IP${NC}"
    fi
    
    echo
    echo -e "${YELLOW}Testing DNS resolution...${NC}"
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution working${NC}"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
    fi
    
    echo
    echo -e "${YELLOW}Testing ping to 8.8.8.8...${NC}"
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Can reach external servers${NC}"
    else
        echo -e "${RED}❌ Cannot reach external servers${NC}"
    fi
    echo
}

# Function to show current network info
show_network_info() {
    echo -e "${CYAN}=== Current Network Information ===${NC}"
    
    echo -e "${YELLOW}Active Network Interfaces:${NC}"
    ip addr show | grep -E "^[0-9]+:" | cut -d: -f2 | tr -d ' ' | while read iface; do
        if [ "$iface" != "lo" ]; then
            ip addr show $iface | grep "inet " | awk -v iface="$iface" '{print "  " iface ": " $2}'
        fi
    done
    
    echo
    echo -e "${YELLOW}Default Gateway:${NC}"
    ip route show default | awk '{print "  " $3 " via " $5}'
    
    echo
    echo -e "${YELLOW}Active Connections:${NC}"
    nmcli connection show --active | grep -v lo
    echo
}

# Function to fix VPN routing
fix_vpn_routing() {
    echo -e "${CYAN}=== VPN Routing Fix Attempts ===${NC}"
    
    # Find VPN interface
    vpn_iface=$(ip link show | grep -E "(wg|tun|tap)" | head -1 | cut -d: -f2 | tr -d ' ')
    
    if [ -z "$vpn_iface" ]; then
        echo -e "${RED}❌ No VPN interface found to fix${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Found VPN interface: $vpn_iface${NC}"
    
    read -p "Attempt to fix routing through $vpn_iface? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipping routing fix${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Attempting to fix default route...${NC}"
    
    # Get VPN gateway if available
    vpn_gateway=$(ip route show dev $vpn_iface | grep -E "default|0\.0\.0\.0" | awk '{print $3}' | head -1)
    
    if [ -n "$vpn_gateway" ]; then
        echo "Using VPN gateway: $vpn_gateway"
        if sudo ip route replace default via $vpn_gateway dev $vpn_iface; then
            echo -e "${GREEN}✓ Default route updated${NC}"
        else
            echo -e "${RED}❌ Failed to update default route${NC}"
        fi
    else
        # Try to add route through VPN interface without specific gateway
        if sudo ip route replace default dev $vpn_iface; then
            echo -e "${GREEN}✓ Default route updated to use VPN interface${NC}"
        else
            echo -e "${RED}❌ Failed to update default route${NC}"
        fi
    fi
    
    echo -e "${YELLOW}Flushing DNS cache...${NC}"
    sudo systemctl restart systemd-resolved 2>/dev/null || sudo service networking restart 2>/dev/null
    
    echo -e "${GREEN}Route fix attempted. Please test connectivity.${NC}"
    echo
}

# Function to restart network services
restart_network_services() {
    echo -e "${CYAN}=== Restarting Network Services ===${NC}"
    
    read -p "Restart NetworkManager and related services? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipping service restart${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Restarting NetworkManager...${NC}"
    sudo systemctl restart NetworkManager
    
    echo -e "${YELLOW}Restarting systemd-resolved...${NC}"
    sudo systemctl restart systemd-resolved 2>/dev/null || echo "systemd-resolved not available"
    
    echo -e "${YELLOW}Restarting systemd-networkd...${NC}"
    sudo systemctl restart systemd-networkd 2>/dev/null || echo "systemd-networkd not available"
    
    sleep 3
    echo -e "${GREEN}Network services restarted${NC}"
    echo
}

# Function to show WireGuard specific info
show_wireguard_info() {
    echo -e "${CYAN}=== WireGuard Specific Information ===${NC}"
    
    if command -v wg >/dev/null 2>&1; then
        echo -e "${YELLOW}WireGuard Status:${NC}"
        sudo wg show
        echo
        
        echo -e "${YELLOW}WireGuard Configuration:${NC}"
        wg_configs=$(find /etc/wireguard -name "*.conf" 2>/dev/null)
        if [ -n "$wg_configs" ]; then
            for config in $wg_configs; do
                echo "Config: $config"
                echo "Interface info:"
                grep -E "(Address|DNS)" "$config" 2>/dev/null | sed 's/^/  /'
            done
        else
            echo "No WireGuard configs found in /etc/wireguard/"
        fi
    else
        echo -e "${RED}WireGuard command 'wg' not found${NC}"
    fi
    echo
}

# Function to run full diagnostic
full_diagnostic() {
    show_header
    echo -e "${GREEN}Running full network diagnostic...${NC}"
    echo
    
    show_network_info
    check_vpn_interface
    check_routing
    check_dns
    show_wireguard_info
    test_connectivity
    
    echo -e "${BLUE}=== SUMMARY ===${NC}"
    echo "If you see issues above, try the fix options in the menu."
    echo
}

# Main menu
main_menu() {
    while true; do
        show_header
        echo -e "${GREEN}Choose diagnostic/fix option:${NC}"
        echo "1. Full Network Diagnostic"
        echo "2. Check VPN Interface Status"
        echo "3. Check Routing Table"
        echo "4. Check DNS Configuration"
        echo "5. Test Connectivity"
        echo "6. Show WireGuard Info"
        echo "7. Fix VPN Routing"
        echo "8. Restart Network Services"
        echo "9. Quick Connection Test"
        echo "10. Exit"
        echo
        read -p "Select option (1-10): " choice
        
        case $choice in
            1)
                full_diagnostic
                read -p "Press Enter to continue..."
                ;;
            2)
                check_vpn_interface
                read -p "Press Enter to continue..."
                ;;
            3)
                check_routing
                read -p "Press Enter to continue..."
                ;;
            4)
                check_dns
                read -p "Press Enter to continue..."
                ;;
            5)
                test_connectivity
                read -p "Press Enter to continue..."
                ;;
            6)
                show_wireguard_info
                read -p "Press Enter to continue..."
                ;;
            7)
                fix_vpn_routing
                read -p "Press Enter to continue..."
                ;;
            8)
                restart_network_services
                read -p "Press Enter to continue..."
                ;;
            9)
                echo -e "${YELLOW}Quick test...${NC}"
                curl -s ifconfig.me && echo " (Your current external IP)"
                read -p "Press Enter to continue..."
                ;;
            10)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if running as root for some operations
if [[ $EUID -eq 0 ]]; then
    echo -e "${YELLOW}Warning: Running as root. Some operations may behave differently.${NC}"
    sleep 2
fi

# Start the main menu
main_menu

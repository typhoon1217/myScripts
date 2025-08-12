#!/bin/bash

# WiFi Manager Script using nmcli
# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    WiFi Connection Manager${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

# Function to check if WiFi is enabled
check_wifi_status() {
    if ! nmcli radio wifi | grep -q "enabled"; then
        echo -e "${RED}WiFi is disabled. Enabling WiFi...${NC}"
        nmcli radio wifi on
        sleep 2
    fi
}

# Function to scan and show available networks
show_available_networks() {
    echo -e "${YELLOW}Scanning for available networks...${NC}"
    nmcli device wifi rescan 2>/dev/null
    sleep 2
    echo
    echo -e "${GREEN}Available WiFi Networks:${NC}"
    echo "----------------------------------------"
    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | \
    awk -F: '{if($1!="") printf "%-30s Signal: %s%% Security: %s\n", $1, $2, $3}' | \
    sort -u | nl -w2 -s'. '
    echo "----------------------------------------"
}

# Function to get available networks as array
get_networks_array() {
    nmcli -t -f SSID device wifi list | grep -v "^$" | sort -u
}

# Function to show saved connections
show_saved_connections() {
    echo -e "${GREEN}Saved WiFi Connections:${NC}"
    echo "----------------------------------------"
    # Look for both "wifi" and "802-11-wireless" type connections
    saved_connections=$(nmcli -t -f NAME,TYPE connection show | grep -E "(wifi|802-11-wireless)" | cut -d: -f1)
    if [ -z "$saved_connections" ]; then
        echo "No saved WiFi connections found."
    else
        echo "$saved_connections" | nl -w2 -s'. '
    fi
    echo "----------------------------------------"
}

# Function to connect to a network
connect_to_network() {
    echo -e "${YELLOW}Scanning for available networks...${NC}"
    nmcli device wifi rescan 2>/dev/null
    sleep 2
    
    # Get networks using a more reliable method to handle spaces in SSID names
    readarray -t networks < <(nmcli -t -f SSID device wifi list | grep -v "^$" | sort -u)
    
    if [ ${#networks[@]} -eq 0 ]; then
        echo -e "${RED}No networks found!${NC}"
        return 1
    fi
    
    echo
    echo -e "${GREEN}Available WiFi Networks:${NC}"
    echo "----------------------------------------"
    
    # Display networks with details and numbers
    for i in "${!networks[@]}"; do
        ssid="${networks[$i]}"
        # Get signal and security info for this SSID
        info=$(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | grep "^${ssid}:" | head -1)
        if [ -n "$info" ]; then
            signal=$(echo "$info" | cut -d: -f2)
            security=$(echo "$info" | cut -d: -f3)
            printf "%2d. %-30s Signal: %s%% Security: %s\n" $((i+1)) "$ssid" "$signal" "$security"
        else
            printf "%2d. %s\n" $((i+1)) "$ssid"
        fi
    done
    echo "----------------------------------------"
    echo "0. Go back to main menu"
    echo
    
    read -p "Select network number (0-${#networks[@]}): " choice
    
    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#networks[@]} ]; then
        echo -e "${RED}Invalid selection!${NC}"
        return 1
    fi
    
    if [ "$choice" -eq 0 ]; then
        return 0
    fi
    
    # Get selected SSID
    ssid="${networks[$((choice-1))]}"
    echo -e "${BLUE}Selected: $ssid${NC}"
    
    # Check if connection already exists
    if nmcli connection show "$ssid" &>/dev/null; then
        echo -e "${YELLOW}Connection profile exists. Attempting to connect...${NC}"
        
        # Try to connect first
        if nmcli connection up "$ssid" 2>/dev/null; then
            echo -e "${GREEN}Successfully connected to $ssid${NC}"
        else
            # If connection failed, likely needs password update
            echo -e "${YELLOW}Connection failed. Network may need password or password update.${NC}"
            read -s -p "Enter password: " password
            echo
            
            if [ -n "$password" ]; then
                # Update the connection with new password and connect
                if nmcli connection modify "$ssid" wifi-sec.psk "$password" && nmcli connection up "$ssid"; then
                    echo -e "${GREEN}Successfully connected to $ssid${NC}"
                else
                    echo -e "${RED}Failed to connect to $ssid. Check password and try again.${NC}"
                fi
            else
                echo -e "${RED}Password cannot be empty for secured network.${NC}"
            fi
        fi
    else
        # New connection - ask for password
        echo -e "${YELLOW}New network detected.${NC}"
        read -s -p "Enter password (press Enter if no password): " password
        echo
        
        if [ -z "$password" ]; then
            # Open network
            if nmcli device wifi connect "$ssid"; then
                echo -e "${GREEN}Successfully connected to $ssid${NC}"
            else
                echo -e "${RED}Failed to connect to $ssid${NC}"
            fi
        else
            # Secured network
            if nmcli device wifi connect "$ssid" password "$password"; then
                echo -e "${GREEN}Successfully connected to $ssid${NC}"
            else
                echo -e "${RED}Failed to connect to $ssid. Check password and try again.${NC}"
            fi
        fi
    fi
}

# Function to disconnect from current network
disconnect_network() {
    active_connections=($(nmcli -t -f NAME connection show --active | grep -v lo))
    
    if [ ${#active_connections[@]} -eq 0 ]; then
        echo -e "${YELLOW}No active connections found.${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Active connections:${NC}"
    echo "----------------------------------------"
    for i in "${!active_connections[@]}"; do
        printf "%2d. %s\n" $((i+1)) "${active_connections[$i]}"
    done
    echo "----------------------------------------"
    echo "0. Go back to main menu"
    echo
    
    read -p "Select connection number to disconnect (0-${#active_connections[@]}): " choice
    
    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#active_connections[@]} ]; then
        echo -e "${RED}Invalid selection!${NC}"
        return 1
    fi
    
    if [ "$choice" -eq 0 ]; then
        return 0
    fi
    
    conn_name="${active_connections[$((choice-1))]}"
    echo -e "${BLUE}Selected: $conn_name${NC}"
    
    if nmcli connection down "$conn_name"; then
        echo -e "${GREEN}Successfully disconnected from $conn_name${NC}"
    else
        echo -e "${RED}Failed to disconnect from $conn_name${NC}"
    fi
}

# Function to remove saved connection
remove_connection() {
    saved_connections=($(nmcli -t -f NAME,TYPE connection show | grep -E "(wifi|802-11-wireless)" | cut -d: -f1))
    
    if [ ${#saved_connections[@]} -eq 0 ]; then
        echo -e "${YELLOW}No saved WiFi connections found.${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Saved WiFi Connections:${NC}"
    echo "----------------------------------------"
    for i in "${!saved_connections[@]}"; do
        printf "%2d. %s\n" $((i+1)) "${saved_connections[$i]}"
    done
    echo "----------------------------------------"
    echo "0. Go back to main menu"
    echo
    
    read -p "Select connection number to remove (0-${#saved_connections[@]}): " choice
    
    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#saved_connections[@]} ]; then
        echo -e "${RED}Invalid selection!${NC}"
        return 1
    fi
    
    if [ "$choice" -eq 0 ]; then
        return 0
    fi
    
    conn_name="${saved_connections[$((choice-1))]}"
    echo -e "${BLUE}Selected: $conn_name${NC}"
    
    read -p "Are you sure you want to remove '$conn_name'? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if nmcli connection delete "$conn_name"; then
            echo -e "${GREEN}Successfully removed connection: $conn_name${NC}"
        else
            echo -e "${RED}Failed to remove connection: $conn_name${NC}"
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
}

# Function to show current status
show_status() {
    echo -e "${GREEN}Current WiFi Status:${NC}"
    echo "----------------------------------------"
    echo "WiFi Radio: $(nmcli radio wifi)"
    echo
    echo "Active Connections:"
    nmcli connection show --active | grep -E "(NAME|wifi)" || echo "No active WiFi connections"
    echo
    echo "Current IP Address:"
    ip addr show $(nmcli -t -f DEVICE connection show --active | head -1 | cut -d: -f1) 2>/dev/null | grep "inet " | awk '{print $2}' || echo "No IP assigned"
    echo "----------------------------------------"
}

# Main menu
main_menu() {
    while true; do
        show_header
        show_status
        echo
        echo -e "${BLUE}Options:${NC}"
        echo "1. Connect to WiFi network"
        echo "2. Disconnect from current network"
        echo "3. Remove saved connection"
        echo "4. Show available networks"
        echo "5. Show saved connections"
        echo "6. Refresh status"
        echo "7. Exit"
        echo
        read -p "Select an option (1-7): " choice
        
        case $choice in
            1)
                check_wifi_status
                connect_to_network
                read -p "Press Enter to continue..."
                ;;
            2)
                disconnect_network
                read -p "Press Enter to continue..."
                ;;
            3)
                remove_connection
                read -p "Press Enter to continue..."
                ;;
            4)
                check_wifi_status
                show_available_networks
                read -p "Press Enter to continue..."
                ;;
            5)
                show_saved_connections
                read -p "Press Enter to continue..."
                ;;
            6)
                continue
                ;;
            7)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if nmcli is available
if ! command -v nmcli &> /dev/null; then
    echo -e "${RED}Error: nmcli (NetworkManager) is not installed or not in PATH${NC}"
    echo "Please install NetworkManager to use this script."
    exit 1
fi

# Start the main menu
main_menu

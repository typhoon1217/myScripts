#!/bin/bash

# wg-status.sh
# Provides a simple, visually appealing check for the WireGuard interface status (non-root).
# IMPORTANT: This script does NOT use sudo and therefore cannot confirm an active VPN handshake.
# It only checks if the 'wg0' network interface is present and active (UP).
# Usage: ./wg-status.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define WireGuard interface name
WG_INTERFACE="wg0"

# Function to get the basic WireGuard interface status (non-root)
# Returns "UP", "DOWN", or "NOT_FOUND".
get_basic_interface_status() {
    # Check if 'ip' command is available
    if ! command -v ip &> /dev/null; then
        echo "IP_COMMAND_MISSING"
        return
    fi

    # Check if the interface exists and is in an UP state
    if ip link show "$WG_INTERFACE" | grep -q "UP,LOWER_UP"; then
        echo "UP"
    elif ip link show "$WG_INTERFACE" &> /dev/null; then
        # Interface exists but is not UP (e.g., state DOWN, NO-CARRIER)
        echo "DOWN"
    else
        # Interface does not exist at all
        echo "NOT_FOUND"
    fi
}

# --- Display VPN Interface Status ---

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          ${CYAN}WireGuard Interface Status${BLUE}                     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"

INTERFACE_STATUS=$(get_basic_interface_status)
STATUS_TEXT=""
STATUS_COLOR=""
STATUS_ICON=""
NOTE_MESSAGE=""

case "$INTERFACE_STATUS" in
    "UP")
        STATUS_TEXT="INTERFACE IS UP"
        STATUS_COLOR="${GREEN}"
        STATUS_ICON="✓"
        NOTE_MESSAGE="(This means 'wg0' is active. Does NOT confirm active VPN handshake.)"
        ;;
    "DOWN")
        STATUS_TEXT="INTERFACE IS DOWN"
        STATUS_COLOR="${YELLOW}"
        STATUS_ICON="⚠"
        NOTE_MESSAGE="(Interface 'wg0' is present but not active. VPN is likely inactive.)"
        ;;
    "NOT_FOUND")
        STATUS_TEXT="INTERFACE NOT FOUND"
        STATUS_COLOR="${RED}"
        STATUS_ICON="✗"
        NOTE_MESSAGE="(The 'wg0' interface does not exist. VPN is definitely not active.)"
        ;;
    "IP_COMMAND_MISSING")
        STATUS_TEXT="ERROR: 'ip' COMMAND MISSING"
        STATUS_COLOR="${RED}"
        STATUS_ICON="!"
        NOTE_MESSAGE="(Cannot check network interface status.)"
        ;;
    *) # Fallback for unexpected status
        STATUS_TEXT="UNKNOWN STATUS"
        STATUS_COLOR="${YELLOW}"
        STATUS_ICON="?"
        NOTE_MESSAGE="(Could not determine 'wg0' interface state.)"
        ;;
esac

# Print the status in a large, centered, colorful format
echo ""
echo -e "         ${STATUS_COLOR}███████████████████████████████████████████████████████████████████${NC}"
echo -e "         ${STATUS_COLOR}█ ${STATUS_TEXT} ${STATUS_ICON} ${NC}"
echo -e "         ${STATUS_COLOR}███████████████████████████████████████████████████████████████████${NC}"
echo ""

# Print the important note
echo -e "${YELLOW}  ${NOTE_MESSAGE}${NC}"
echo -e "${YELLOW}  For definitive WireGuard VPN connection status (active handshakes),${NC}"
echo -e "${YELLOW}  please use the main script with root privileges: ${CYAN}sudo ./wg-manager.sh status${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

exit 0


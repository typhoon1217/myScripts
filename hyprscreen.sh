#!/bin/bash

# Dynamic Monitor Order Switcher for Hyprland
# Automatically detects connected monitors and provides switching options

# Global variables
declare -a MONITORS
declare -a ALL_MONITORS
declare -a MONITOR_INFO
declare -a ALL_MONITOR_INFO
RESOLUTION_SUFFIX="@60" # This variable is mostly illustrative, not actively used for resolution selection now
SCALE="1"

# Function to get all available monitors (including disabled ones)
get_all_monitors() {
    ALL_MONITORS=()
    ALL_MONITOR_INFO=()
    
    # Get all possible monitors from wlr-randr or fallback detection
    if command -v wlr-randr >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [[ $line =~ ^([A-Za-z0-9-]+)\ \".*\"$ ]]; then
                local monitor_name="${BASH_REMATCH[1]}"
                ALL_MONITORS+=("$monitor_name")
                # For all monitors, try to get preferred resolution using the improved function
                local resolution=$(get_monitor_resolution "$monitor_name")
                ALL_MONITOR_INFO+=("$resolution")
            fi
        done < <(wlr-randr --version >/dev/null 2>&1 && wlr-randr)
    fi
    
    # Also check common laptop display names if not found
    local common_laptop_displays=("eDP-1" "LVDS-1" "DSI-1" "eDP-2")
    for display in "${common_laptop_displays[@]}"; do
        if [[ ! " ${ALL_MONITORS[*]} " =~ " $display " ]]; then
            # Test if this display exists by trying to query it
            if hyprctl keyword monitor "$display,preferred,auto,1" 2>/dev/null; then
                ALL_MONITORS+=("$display")
                ALL_MONITOR_INFO+=("1920x1080@60") # Default for newly discovered laptop displays
                echo "🔍 Found hidden laptop display: $display"
            fi
        fi
    done
    
    echo "🔍 Total available monitors: ${#ALL_MONITORS[@]} (${ALL_MONITORS[*]})"
}

# Function to get currently active monitors
get_monitors() {
    MONITORS=()
    MONITOR_INFO=()
    
    # Parse hyprctl monitors output
    while IFS= read -r line; do
        if [[ $line =~ ^Monitor\ ([^\ ]+)\ \(ID\ ([0-9]+)\): ]]; then
            local monitor_name="${BASH_REMATCH[1]}"
            local monitor_id="${BASH_REMATCH[2]}"
            MONITORS+=("$monitor_name")
        elif [[ $line =~ ^[[:space:]]+([0-9]+x[0-9]+)@([0-9.]+)\ at\ ([0-9]+x[0-9]+) ]]; then
            local resolution="${BASH_REMATCH[1]}"
            local refresh="${BASH_REMATCH[2]}"
            local position="${BASH_REMATCH[3]}"
            MONITOR_INFO+=("$resolution@$refresh:$position")
        fi
    done < <(hyprctl monitors)
    
    echo "🔍 Currently active: ${#MONITORS[@]} monitor(s): ${MONITORS[*]}"
    
    if [[ ${#MONITORS[@]} -eq 0 ]]; then
        echo "⚠️  No active monitors detected - checking for disabled monitors..."
        get_all_monitors
        enable_all_monitors
        return
    fi
}

# Function to enable all available monitors
enable_all_monitors() {
    echo "🔋 Enabling all available monitors..."
    
    # First, get all possible monitors
    get_all_monitors
    
    if [[ ${#ALL_MONITORS[@]} -eq 0 ]]; then
        echo "❌ No monitors found to enable"
        return 1
    fi
    
    local x_offset=0
    local config=()
    
    for i in "${!ALL_MONITORS[@]}"; do
        local monitor="${ALL_MONITORS[$i]}"
        # Use the smart resolution getter to pick the best resolution
        local resolution=$(get_monitor_resolution "$monitor")
        
        echo "  ✅ Enabling $monitor at position ${x_offset}x0 with resolution $resolution"
        config+=("$monitor,$resolution,${x_offset}x0,$SCALE")
        
        # Determine width for offset based on the chosen resolution
        local width=$(echo "$resolution" | cut -d'x' -f1)
        x_offset=$((x_offset + width))
    done
    
    apply_config "${config[@]}"
    
    # Refresh monitor list after enabling
    sleep 1
    get_monitors
    echo "✅ All monitors enabled! Current active monitors: ${#MONITORS[@]}"
}

# Function to force enable a specific monitor
force_enable_monitor() {
    echo "🎯 Select a monitor to force enable:"
    echo ""
    
    # Show common monitor names
    local common_monitors=("eDP-1" "LVDS-1" "DSI-1" "HDMI-A-1" "HDMI-A-2" "DP-1" "DP-2" "DVI-D-1")
    
    echo "Common monitor names:"
    for i in "${!common_monitors[@]}"; do
        echo "  $((i+1))) ${common_monitors[$i]}"
    done
    echo "  c) Custom monitor name"
    echo "  0) Cancel"
    echo ""
    
    read -p "Enter choice: " choice
    
    local selected_monitor=""
    
    if [[ $choice =~ ^[0-9]+$ ]] && [[ $choice -gt 0 ]] && [[ $choice -le ${#common_monitors[@]} ]]; then
        selected_monitor="${common_monitors[$((choice-1))]}"
    elif [[ $choice == "c" || $choice == "C" ]]; then
        read -p "Enter monitor name: " selected_monitor
    elif [[ $choice == "0" ]]; then
        return 0
    else
        echo "❌ Invalid choice"
        return 1
    fi
    
    if [[ -z "$selected_monitor" ]]; then
        echo "❌ No monitor selected"
        return 1
    fi
    
    echo "🔧 Force enabling monitor: $selected_monitor"
    
    # Try different resolution settings, including preferred and detected highest
    local resolutions=()
    local detected_highest_res=$(get_monitor_resolution "$selected_monitor")
    if [[ "$detected_highest_res" != "preferred" && "$detected_highest_res" != "1920x1080@60" ]]; then
        resolutions+=("$detected_highest_res") # Add the detected highest resolution first
    fi
    resolutions+=("preferred" "1920x1080@60" "1366x768@60" "auto") # Fallbacks
    
    for res in "${resolutions[@]}"; do
        echo "  Trying resolution: $res"
        if hyprctl keyword monitor "$selected_monitor,$res,auto,$SCALE" 2>/dev/null; then
            echo "✅ Successfully enabled $selected_monitor with resolution $res"
            sleep 1
            get_monitors
            return 0
        fi
    done
    
    echo "❌ Failed to enable $selected_monitor - monitor may not exist or be connected"
    return 1
}

# Function to get monitor resolution and refresh rate (Enhanced to find highest available)
get_monitor_resolution() {
    local monitor_name="$1"
    local highest_resolution=""
    local highest_width=0
    local highest_height=0
    local current_monitor_parsing="" # Use a different variable name to avoid conflict
    local found_current_active=false
    local current_active_res_for_fallback="preferred" # Default fallback
    
    # Parse hyprctl monitors output
    while IFS= read -r line; do
        if [[ $line =~ ^Monitor\ ([^\ ]+)\ \(ID\ ([0-9]+)\): ]]; then
            current_monitor_parsing="${BASH_REMATCH[1]}"
            # Reset found_current_active for the new monitor
            found_current_active=false
        elif [[ "$current_monitor_parsing" == "$monitor_name" ]]; then
            # Capture the currently active resolution for fallback (marked by a '*' in hyprctl)
            if [[ $line =~ ^[[:space:]]+([0-9]+x[0-9]+)@([0-9.]+)\ at\ ([0-9]+x[0-9]+) && $line =~ \* ]]; then
                current_active_res_for_fallback="${BASH_REMATCH[1]}@${BASH_REMATCH[2]}"
                found_current_active=true
            fi
            
            # Look for availableModes line (Hyprland 0.38.0 and newer)
            if [[ $line =~ ^[[:space:]]+availableModes:\ (.+) ]]; then
                local modes_string="${BASH_REMATCH[1]}"
                IFS=' ' read -ra MODES <<< "$modes_string"
                for mode in "${MODES[@]}"; do
                    # Extract resolution (e.g., 3440x1440) and refresh rate (e.g., @59.97Hz)
                    if [[ $mode =~ ^([0-9]+x[0-9]+)@([0-9.]+)\Hz$ ]]; then
                        local res_part="${BASH_REMATCH[1]}"
                        local refresh_part="${BASH_REMATCH[2]}"
                        local width=$(echo "$res_part" | cut -d'x' -f1)
                        local height=$(echo "$res_part" | cut -d'x' -f2)
                        
                        # Check if this mode is higher resolution than current highest
                        if (( width * height > highest_width * highest_height )); then
                            highest_width="$width"
                            highest_height="$height"
                            highest_resolution="${res_part}@${refresh_part}"
                        fi
                    fi
                done
                break # Found available modes for this monitor, no need to read further
            fi
        fi
    done < <(hyprctl monitors)
    
    if [[ -n "$highest_resolution" ]]; then
        echo "$highest_resolution"
    elif [[ "$found_current_active" == true ]]; then
        # Fallback to current active resolution if no availableModes or higher resolution is found
        echo "$current_active_res_for_fallback"
    else
        # Last resort fallback if nothing is found (e.g., monitor disabled or no info)
        echo "preferred"
    fi
}

# Function to disable specific monitors
disable_monitor() {
    if [[ ${#MONITORS[@]} -eq 0 ]]; then
        echo "❌ No active monitors to disable"
        return 1
    fi
    
    echo "🚫 Select monitor to disable:"
    for i in "${!MONITORS[@]}"; do
        echo "  $((i+1))) ${MONITORS[$i]}"
    done
    echo "  0) Cancel"
    echo ""
    
    read -p "Enter choice: " choice
    
    if [[ $choice == "0" ]]; then
        return 0
    elif [[ $choice =~ ^[0-9]+$ ]] && [[ $choice -gt 0 ]] && [[ $choice -le ${#MONITORS[@]} ]]; then
        local monitor="${MONITORS[$((choice-1))]}"
        echo "🚫 Disabling monitor: $monitor"
        hyprctl keyword monitor "$monitor,disable"
        echo "✅ Monitor $monitor disabled"
        sleep 1
        get_monitors
    else
        echo "❌ Invalid choice"
    fi
}

# Function to apply monitor configuration
apply_config() {
    local config=("$@")
    echo "🔧 Applying configuration..."
    
    for monitor_config in "${config[@]}"; do
        echo "  Setting: $monitor_config"
        hyprctl keyword monitor "$monitor_config"
    done
}

# Quick laptop screen recovery function
recover_laptop_screen() {
    echo "💻 Attempting to recover laptop screen..."
    
    local laptop_displays=("eDP-1" "LVDS-1" "DSI-1" "eDP-2")
    local success=false
    
    for display in "${laptop_displays[@]}"; do
        echo "  Trying $display..."
        # Use 'preferred' for recovery, then re-arrange with accurate resolutions
        if hyprctl keyword monitor "$display,preferred,0x0,1" 2>/dev/null; then
            echo "✅ Successfully recovered laptop screen: $display"
            success=true
            
            # If there are other monitors, arrange them properly
            if [[ ${#MONITORS[@]} -gt 0 ]]; then
                echo "  Arranging with existing monitors..."
                sleep 1
                get_monitors
                horizontal_arrangement # This will now use the correct resolutions
            fi
            break
        fi
    done
    
    if [[ $success == false ]]; then
        echo "❌ Could not recover laptop screen. Try 'Enable All Monitors' option."
    fi
}

# Two monitor configurations
two_monitor_swap() {
    if [[ ${#MONITORS[@]} -ne 2 ]]; then
        echo "❌ This function requires exactly 2 monitors"
        return 1
    fi
    
    local mon1="${MONITORS[0]}" # Original left monitor
    local mon2="${MONITORS[1]}" # Original right monitor
    
    # Get the resolutions for the two monitors
    local res1=$(get_monitor_resolution "$mon1")
    local res2=$(get_monitor_resolution "$mon2")
    
    # Extract the width of the monitor that will be on the left (mon2's width)
    local mon2_width=$(echo "$res2" | cut -d'x' -f1)
    
    echo "🔄 Swapping monitor order:"
    echo "  $mon2 → Left (0x0) at $res2"
    echo "  $mon1 → Right (${mon2_width}x0) at $res1" # Position mon1 based on mon2's width
    
    apply_config \
        "$mon2,$res2,0x0,$SCALE" \
        "$mon1,$res1,${mon2_width}x0,$SCALE" # Use calculated offset
}

# Horizontal arrangement (left to right)
horizontal_arrangement() {
    local x_offset=0
    local config=()
    
    echo "➡️  Setting horizontal arrangement (left to right):"
    
    for i in "${!MONITORS[@]}"; do
        local monitor="${MONITORS[$i]}"
        local resolution=$(get_monitor_resolution "$monitor")
        local width=$(echo "$resolution" | cut -d'x' -f1)
        
        echo "  $monitor → Position ${x_offset}x0 (Resolution: $resolution)"
        config+=("$monitor,$resolution,${x_offset}x0,$SCALE")
        
        x_offset=$((x_offset + width))
    done
    
    apply_config "${config[@]}"
}

# Reverse horizontal arrangement (right to left order)
reverse_horizontal() {
    local x_offset=0
    local config=()
    local reversed_monitors=()
    
    # Reverse the monitors array
    for (( i=${#MONITORS[@]}-1 ; i>=0 ; i-- )); do
        reversed_monitors+=("${MONITORS[$i]}")
    done
    
    echo "⬅️  Setting reverse horizontal arrangement:"
    
    for monitor in "${reversed_monitors[@]}"; do
        local resolution=$(get_monitor_resolution "$monitor")
        local width=$(echo "$resolution" | cut -d'x' -f1)
        
        echo "  $monitor → Position ${x_offset}x0 (Resolution: $resolution)"
        config+=("$monitor,$resolution,${x_offset}x0,$SCALE")
        
        x_offset=$((x_offset + width))
    done
    
    apply_config "${config[@]}"
}

# Vertical arrangement (top to bottom)
vertical_arrangement() {
    local y_offset=0
    local config=()
    
    echo "⬇️  Setting vertical arrangement (top to bottom):"
    
    for monitor in "${MONITORS[@]}"; do
        local resolution=$(get_monitor_resolution "$monitor")
        local height=$(echo "$resolution" | cut -d'x' -f2 | cut -d'@' -f1)
        
        echo "  $monitor → Position 0x${y_offset} (Resolution: $resolution)"
        config+=("$monitor,$resolution,0x${y_offset},$SCALE")
        
        y_offset=$((y_offset + height))
    done
    
    apply_config "${config[@]}"
}

# Reverse vertical arrangement (bottom to top order)
reverse_vertical() {
    local y_offset=0
    local config=()
    local reversed_monitors=()
    
    # Reverse the monitors array
    for (( i=${#MONITORS[@]}-1 ; i>=0 ; i-- )); do
        reversed_monitors+=("${MONITORS[$i]}")
    done
    
    echo "⬆️  Setting reverse vertical arrangement:"
    
    for monitor in "${reversed_monitors[@]}"; do
        local resolution=$(get_monitor_resolution "$monitor")
        local height=$(echo "$resolution" | cut -d'x' -f2 | cut -d'@' -f1)
        
        echo "  $monitor → Position 0x${y_offset} (Resolution: $resolution)"
        config+=("$monitor,$resolution,0x${y_offset},$SCALE")
        
        y_offset=$((y_offset + height))
    done
    
    apply_config "${config[@]}"
}

# Mirror all displays
mirror_displays() {
    local config=()
    
    echo "🪞 Setting mirror mode (all displays at 0x0):"
    
    for monitor in "${MONITORS[@]}"; do
        local resolution=$(get_monitor_resolution "$monitor")
        echo "  $monitor → Mirrored at 0x0 (Resolution: $resolution)"
        config+=("$monitor,$resolution,0x0,$SCALE")
    done
    
    apply_config "${config[@]}"
}

# Enable only first monitor
primary_only() {
    local primary="${MONITORS[0]}"
    local primary_res=$(get_monitor_resolution "$primary")
    local config=("$primary,$primary_res,0x0,$SCALE")
    
    echo "💻 Setting primary monitor only: $primary (Resolution: $primary_res)"
    
    # Disable other monitors
    for (( i=1; i<${#MONITORS[@]}; i++ )); do
        echo "  Disabling: ${MONITORS[$i]}"
        config+=("${MONITORS[$i]},disable")
    done
    
    apply_config "${config[@]}"
}

# Enable only last monitor
secondary_only() {
    if [[ ${#MONITORS[@]} -lt 2 ]]; then
        echo "❌ Only one monitor available"
        return 1
    fi
    
    local secondary="${MONITORS[-1]}"
    local secondary_res=$(get_monitor_resolution "$secondary")
    local config=("$secondary,$secondary_res,0x0,$SCALE")
    
    echo "🖥️  Setting secondary monitor only: $secondary (Resolution: $secondary_res)"
    
    # Disable other monitors
    for (( i=0; i<${#MONITORS[@]}-1; i++ )); do
        echo "  Disabling: ${MONITORS[$i]}"
        config+=("${MONITORS[$i]},disable")
    done
    
    apply_config "${config[@]}"
}

# Custom arrangement selector
custom_arrangement() {
    echo "🎯 Custom Monitor Arrangement"
    echo "Available monitors:"
    for i in "${!MONITORS[@]}"; do
        echo "  $((i+1))) ${MONITORS[$i]} - $(get_monitor_resolution "${MONITORS[$i]}")"
    done
    echo ""
    
    read -p "Enter monitor order (e.g., 2,1,3): " order
    IFS=',' read -ra ORDER_ARRAY <<< "$order"
    
    local x_offset=0
    local config=()
    
    for order_idx in "${ORDER_ARRAY[@]}"; do
        local monitor_idx=$((order_idx - 1))
        
        if [[ $monitor_idx -ge 0 && $monitor_idx -lt ${#MONITORS[@]} ]]; then
            local monitor="${MONITORS[$monitor_idx]}"
            local resolution=$(get_monitor_resolution "$monitor")
            local width=$(echo "$resolution" | cut -d'x' -f1)
            
            echo "  $monitor → Position ${x_offset}x0 (Resolution: $resolution)"
            config+=("$monitor,$resolution,${x_offset}x0,$SCALE")
            
            x_offset=$((x_offset + width))
        else
            echo "❌ Invalid monitor index: $order_idx"
            return 1
        fi
    done
    
    apply_config "${config[@]}"
}

# Get current configuration
get_current_config() {
    echo "📊 Current Monitor Configuration:"
    echo "================================="
    
    local monitor_count=0
    while IFS= read -r line; do
        if [[ $line =~ ^Monitor\ ([^\ ]+)\ \(ID\ ([0-9]+)\): ]]; then
            monitor_count=$((monitor_count + 1))
            echo "🖥️  Monitor: ${BASH_REMATCH[1]} (ID: ${BASH_REMATCH[2]})"
        elif [[ $line =~ ^[[:space:]]+([0-9]+x[0-9]+)@([0-9.]+)\ at\ ([0-9]+x[0-9]+) ]]; then
            echo "    Resolution: ${BASH_REMATCH[1]}@${BASH_REMATCH[2]}"
            echo "    Position: ${BASH_REMATCH[3]}"
        elif [[ $line =~ ^[[:space:]]+description:\ (.+) ]]; then
            echo "    Description: ${BASH_REMATCH[1]}"
        elif [[ $line =~ ^[[:space:]]+focused:\ (yes|no) ]]; then
            echo "    Focused: ${BASH_REMATCH[1]}"
            echo ""
        fi
    done < <(hyprctl monitors)
    
    echo "Total active monitors: $monitor_count"
}

# Interactive menu
interactive_menu() {
    while true; do
        echo ""
        echo "🔧 Dynamic Hyprland Monitor Configuration"
        echo "========================================"
        get_current_config
        echo "Choose configuration:"
        echo ""
        echo "🔋 Recovery Options:"
        echo "a) Enable ALL monitors (scan and enable everything)"
        echo "l) Recover laptop screen (try common laptop displays)"
        echo "e) Force enable specific monitor"
        echo "d) Disable specific monitor"
        echo ""
        echo "📐 Arrangement Options:"
        
        if [[ ${#MONITORS[@]} -eq 2 ]]; then
            echo "1) Swap monitor order"
        fi
        
        echo "2) Horizontal arrangement (current order)"
        echo "3) Reverse horizontal arrangement" 
        echo "4) Vertical arrangement (current order)"
        echo "5) Reverse vertical arrangement"
        echo "6) Mirror all displays"
        echo "7) Primary monitor only (${MONITORS[0]:-"none"})"
        
        if [[ ${#MONITORS[@]} -gt 1 ]]; then
            echo "8) Secondary monitor only (${MONITORS[-1]})"
        fi
        
        echo "9) Custom arrangement"
        echo ""
        echo "ℹ️  Info Options:"
        echo "s) Show current config"
        echo "r) Refresh monitor detection"  
        echo "0) Exit"
        echo ""
        read -p "Enter choice: " choice
        
        case $choice in
            a|A) enable_all_monitors ;;
            l|L) recover_laptop_screen ;;
            e|E) force_enable_monitor ;;
            d|D) disable_monitor ;;
            1) [[ ${#MONITORS[@]} -eq 2 ]] && two_monitor_swap || echo "❌ Option only available with 2 monitors" ;;
            2) horizontal_arrangement ;;
            3) reverse_horizontal ;;
            4) vertical_arrangement ;;
            5) reverse_vertical ;;
            6) mirror_displays ;;
            7) [[ ${#MONITORS[@]} -gt 0 ]] && primary_only || echo "❌ No monitors available" ;;
            8) [[ ${#MONITORS[@]} -gt 1 ]] && secondary_only || echo "❌ Only one monitor available" ;;
            9) custom_arrangement ;;
            s|S) get_current_config ;;
            r|R) get_monitors ;;
            0) echo "👋 Goodbye!"; exit 0 ;;
            *) echo "❌ Invalid choice" ;;
        esac
        
        if [[ "$choice" != "s" && "$choice" != "S" && "$choice" != "r" && "$choice" != "R" ]]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# Help function
show_help() {
    echo "Dynamic Monitor Order Switcher for Hyprland"
    echo "Automatically detects connected monitors"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Recovery Options:"
    echo "  enable-all      Enable all available monitors"
    echo "  recover-laptop  Try to recover laptop screen"
    echo "  force-enable    Force enable a specific monitor"
    echo ""
    echo "Arrangement Options:"
    echo "  horizontal      Arrange monitors horizontally (left to right)"
    echo "  reverse-h       Reverse horizontal arrangement"
    echo "  vertical        Arrange monitors vertically (top to bottom)"
    echo "  reverse-v       Reverse vertical arrangement"
    echo "  mirror          Mirror all displays"
    echo "  primary-only    Enable only the first monitor"
    echo "  secondary-only  Enable only the last monitor"
    echo "  swap            Swap order (2 monitors only)"
    echo "  custom          Custom arrangement selector"
    echo ""
    echo "Info Options:"
    echo "  status          Show current configuration"
    echo "  interactive     Interactive menu (default)"
    echo "  help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 enable-all"
    echo "  $0 recover-laptop"
    echo "  $0 reverse-h"
    echo "  $0 vertical"
}

# Main execution
main() {
    # Check if hyprctl is available
    command -v hyprctl >/dev/null 2>&1 || { 
        echo "❌ hyprctl not found. Are you running Hyprland?"
        exit 1
    }
    
    # Get monitor information initially
    get_monitors
    
    case "${1:-interactive}" in
        "enable-all")       enable_all_monitors ;;
        "recover-laptop")   recover_laptop_screen ;;
        "force-enable")     force_enable_monitor ;;
        "horizontal")       horizontal_arrangement ;;
        "reverse-h")        reverse_horizontal ;;
        "vertical")         vertical_arrangement ;;
        "reverse-v")        reverse_vertical ;;
        "mirror")           mirror_displays ;;
        "primary-only")     primary_only ;;
        "secondary-only")   secondary_only ;;
        "swap")             two_monitor_swap ;;
        "custom")           custom_arrangement ;;
        "status")           get_current_config ;;
        "interactive")      interactive_menu ;;
        "help"|"-h"|"--help") show_help ;;
        *)  
            echo "❌ Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

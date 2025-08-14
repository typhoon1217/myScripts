#!/bin/zsh
# Btrfs snapshot restoration script
# DANGER: This script modifies your filesystem. Use with extreme caution!
# Run as root (e.g., with sudo)

# Configuration
SNAPSHOT_DIR="/snapshots"
BTRFS_ROOT="/mnt/btrfs-root"  # Temporary mount point for Btrfs root

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root. Please use sudo.${NC}"
    exit 1
fi

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

# Function to confirm dangerous operations
confirm_action() {
    local message="$1"
    local response
    
    print_status "$YELLOW" "$message"
    print_status "$YELLOW" "Type 'YES' (in capitals) to confirm, or anything else to cancel:"
    read -r response
    
    if [[ "$response" != "YES" ]]; then
        print_status "$RED" "Operation cancelled by user."
        exit 0
    fi
}

# Function to list available snapshots
list_snapshots() {
    local subvol_prefix="$1"
    
    if [[ -z "$subvol_prefix" ]]; then
        echo "Available snapshots:"
        ls -la "$SNAPSHOT_DIR" 2>/dev/null || {
            print_status "$RED" "No snapshots found in $SNAPSHOT_DIR"
            return 1
        }
    else
        echo "Available snapshots for $subvol_prefix:"
        ls -la "$SNAPSHOT_DIR" | grep "$subvol_prefix" 2>/dev/null || {
            print_status "$RED" "No snapshots found for $subvol_prefix"
            return 1
        }
    fi
}

# Function to get Btrfs root device
get_btrfs_device() {
    local mount_point="$1"
    findmnt -n -o SOURCE "$mount_point" 2>/dev/null | head -1
}

# Function to mount Btrfs root
mount_btrfs_root() {
    local device="$1"
    
    print_status "$BLUE" "Mounting Btrfs root filesystem..."
    
    # Create mount point
    mkdir -p "$BTRFS_ROOT"
    
    # Mount with subvolid=5 to access the root of the Btrfs filesystem
    if mount -o subvolid=5 "$device" "$BTRFS_ROOT"; then
        print_status "$GREEN" "Successfully mounted Btrfs root at $BTRFS_ROOT"
        return 0
    else
        print_status "$RED" "Failed to mount Btrfs root filesystem"
        return 1
    fi
}

# Function to unmount Btrfs root
unmount_btrfs_root() {
    if mountpoint -q "$BTRFS_ROOT"; then
        print_status "$BLUE" "Unmounting Btrfs root..."
        umount "$BTRFS_ROOT"
        rmdir "$BTRFS_ROOT" 2>/dev/null
    fi
}

# Function to restore a subvolume
restore_subvolume() {
    local snapshot_path="$1"
    local subvol_name="$2"
    local device="$3"
    
    print_status "$BLUE" "Starting restoration of $subvol_name from $snapshot_path"
    
    # Verify snapshot exists and is a valid subvolume
    if ! btrfs subvolume show "$snapshot_path" &>/dev/null; then
        print_status "$RED" "Error: Invalid snapshot at $snapshot_path"
        return 1
    fi
    
    # Mount Btrfs root if not already mounted
    if ! mountpoint -q "$BTRFS_ROOT"; then
        mount_btrfs_root "$device" || return 1
    fi
    
    # Create backup of current subvolume
    local backup_name="${subvol_name}_backup_$(date +%Y%m%d_%H%M%S)"
    print_status "$YELLOW" "Creating backup of current subvolume as $backup_name"
    
    if btrfs subvolume snapshot "$BTRFS_ROOT/$subvol_name" "$BTRFS_ROOT/$backup_name"; then
        print_status "$GREEN" "Backup created successfully"
    else
        print_status "$RED" "Failed to create backup. Aborting restoration."
        return 1
    fi
    
    # Delete current subvolume
    print_status "$YELLOW" "Deleting current subvolume $subvol_name"
    if ! btrfs subvolume delete "$BTRFS_ROOT/$subvol_name"; then
        print_status "$RED" "Failed to delete current subvolume. Restoration aborted."
        print_status "$YELLOW" "Your backup is still available at $BTRFS_ROOT/$backup_name"
        return 1
    fi
    
    # Create writable snapshot from the backup
    print_status "$BLUE" "Creating new subvolume from snapshot..."
    if btrfs subvolume snapshot "$snapshot_path" "$BTRFS_ROOT/$subvol_name"; then
        print_status "$GREEN" "Successfully restored $subvol_name from snapshot"
        print_status "$YELLOW" "Backup of previous state available at $BTRFS_ROOT/$backup_name"
        return 0
    else
        print_status "$RED" "Failed to restore from snapshot!"
        print_status "$YELLOW" "Attempting to restore from backup..."
        
        # Try to restore from backup
        if btrfs subvolume snapshot "$BTRFS_ROOT/$backup_name" "$BTRFS_ROOT/$subvol_name"; then
            print_status "$YELLOW" "Original subvolume restored from backup"
        else
            print_status "$RED" "CRITICAL: Failed to restore original subvolume!"
            print_status "$RED" "Manual intervention required. Backup is at $BTRFS_ROOT/$backup_name"
        fi
        return 1
    fi
}

# Function for interactive restoration
interactive_restore() {
    print_status "$BLUE" "=== Interactive Btrfs Snapshot Restoration ==="
    
    # List available snapshots
    if ! list_snapshots; then
        exit 1
    fi
    
    echo
    print_status "$YELLOW" "Enter the full snapshot path (from $SNAPSHOT_DIR):"
    read -r snapshot_path
    
    if [[ ! -d "$snapshot_path" ]]; then
        print_status "$RED" "Error: Snapshot path does not exist: $snapshot_path"
        exit 1
    fi
    
    # Extract subvolume name from snapshot path
    local snapshot_basename=$(basename "$snapshot_path")
    local subvol_name="${snapshot_basename%-*}"  # Remove timestamp suffix
    
    print_status "$BLUE" "Detected subvolume: $subvol_name"
    print_status "$BLUE" "Snapshot: $snapshot_path"
    
    # Get the device for the root filesystem
    local device=$(get_btrfs_device "/")
    if [[ -z "$device" ]]; then
        print_status "$RED" "Error: Could not determine Btrfs device"
        exit 1
    fi
    
    print_status "$BLUE" "Btrfs device: $device"
    
    # Final confirmation
    confirm_action "This will restore subvolume '$subvol_name' from snapshot '$snapshot_basename'. This action is IRREVERSIBLE (though a backup will be created). Continue?"
    
    # Perform restoration
    if restore_subvolume "$snapshot_path" "$subvol_name" "$device"; then
        print_status "$GREEN" "Restoration completed successfully!"
        print_status "$YELLOW" "You may need to reboot for changes to take full effect."
    else
        print_status "$RED" "Restoration failed!"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -l, --list [SUBVOL]     List available snapshots (optionally for specific subvolume)"
    echo "  -r, --restore PATH      Restore from specific snapshot path"
    echo "  -i, --interactive       Interactive restoration mode"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --list                           # List all snapshots"
    echo "  $0 --list @                         # List snapshots for @ subvolume"
    echo "  $0 --restore /snapshots/@-20241201_120000  # Restore specific snapshot"
    echo "  $0 --interactive                    # Interactive mode"
}

# Cleanup function
cleanup() {
    unmount_btrfs_root
}

# Set trap for cleanup
trap cleanup EXIT

# Main script logic
case "${1:-}" in
    -l|--list)
        list_snapshots "$2"
        ;;
    -r|--restore)
        if [[ -z "$2" ]]; then
            print_status "$RED" "Error: Snapshot path required for restore option"
            show_usage
            exit 1
        fi
        
        snapshot_path="$2"
        snapshot_basename=$(basename "$snapshot_path")
        subvol_name="${snapshot_basename%-*}"
        device=$(get_btrfs_device "/")
        
        confirm_action "Restore subvolume '$subvol_name' from '$snapshot_basename'?"
        
        if restore_subvolume "$snapshot_path" "$subvol_name" "$device"; then
            print_status "$GREEN" "Restoration completed successfully!"
        else
            exit 1
        fi
        ;;
    -i|--interactive)
        interactive_restore
        ;;
    -h|--help)
        show_usage
        ;;
    "")
        interactive_restore
        ;;
    *)
        print_status "$RED" "Error: Unknown option: $1"
        show_usage
        exit 1
        ;;
esac

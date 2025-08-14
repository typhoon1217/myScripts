#!/bin/zsh
# Btrfs snapshot creation script with proper subvolume handling
# Run as root (e.g., with sudo)

# Configuration
SNAPSHOT_DIR="/snapshots"            # Directory for snapshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)     # Unique timestamp for snapshots
KEEP_SNAPS=5                         # Number of snapshots to keep locally

# Define subvolumes with their mount points
# Adjust these paths based on your actual Btrfs setup
declare -A SUBVOLUMES=(
    ["@"]="/"
    ["@home"]="/home"
)

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root. Please use sudo."
    exit 1
fi

# Verify Btrfs filesystem
if ! command -v btrfs &> /dev/null; then
    echo "Error: btrfs command not found. Please install btrfs-progs."
    exit 1
fi

# Create snapshot directory if it doesn't exist
if ! mkdir -p "$SNAPSHOT_DIR"; then
    echo "Error: Failed to create snapshot directory at $SNAPSHOT_DIR."
    exit 1
fi

# Function to clean up old snapshots
cleanup_snapshots() {
    local dir="$1"
    local prefix="$2"
    local keep="$3"
    
    echo "Cleaning up old snapshots for $prefix..."
    
    # Find and sort snapshots, keep only the specified number
    local snapshots=($(ls -d "$dir/$prefix"* 2>/dev/null | sort -r))
    local total=${#snapshots[@]}
    
    if (( total > keep )); then
        local to_delete=(${snapshots[@]:$keep})
        for snap in "${to_delete[@]}"; do
            if btrfs subvolume delete "$snap" 2>/dev/null; then
                echo "Deleted old snapshot: $snap"
            else
                echo "Warning: Failed to delete snapshot: $snap"
            fi
        done
    fi
}

# Function to create snapshot for a subvolume
create_snapshot() {
    local subvol_name="$1"
    local mount_point="$2"
    local snapshot_path="$SNAPSHOT_DIR/$subvol_name-$TIMESTAMP"
    
    echo "Creating snapshot for subvolume '$subvol_name' (mounted at $mount_point)..."
    
    # Verify the mount point exists and is a Btrfs subvolume
    if ! mountpoint -q "$mount_point"; then
        echo "Warning: $mount_point is not a mount point, skipping $subvol_name"
        return 1
    fi
    
    # Create read-only snapshot
    if btrfs subvolume snapshot -r "$mount_point" "$snapshot_path"; then
        sync  # Ensure snapshot is written to disk
        echo "Success: Snapshot created at $snapshot_path"
        
        # Verify snapshot was created successfully
        if btrfs subvolume show "$snapshot_path" &>/dev/null; then
            echo "Verified: Snapshot is valid"
        else
            echo "Error: Snapshot verification failed for $snapshot_path"
            return 1
        fi
    else
        echo "Error: Failed to create snapshot for $subvol_name at $mount_point"
        return 1
    fi
}

# Main execution
echo "Starting Btrfs snapshot process at $(date)"
echo "Snapshot directory: $SNAPSHOT_DIR"
echo "Timestamp: $TIMESTAMP"
echo "Snapshots to keep: $KEEP_SNAPS"
echo "----------------------------------------"

# Track success/failure
declare -a failed_snapshots=()
declare -a successful_snapshots=()

# Create snapshots for each subvolume
for subvol_name in "${(@k)SUBVOLUMES}"; do
    mount_point="${SUBVOLUMES[$subvol_name]}"
    
    if create_snapshot "$subvol_name" "$mount_point"; then
        successful_snapshots+=("$subvol_name")
        
        # Clean up old snapshots for this subvolume
        cleanup_snapshots "$SNAPSHOT_DIR" "$subvol_name-" "$KEEP_SNAPS"
    else
        failed_snapshots+=("$subvol_name")
    fi
    
    echo "----------------------------------------"
done

# Final report
echo "Snapshot process completed at $(date)"
echo "Successful snapshots: ${#successful_snapshots[@]}"
for subvol in "${successful_snapshots[@]}"; do
    echo "  ✓ $subvol"
done

if (( ${#failed_snapshots[@]} > 0 )); then
    echo "Failed snapshots: ${#failed_snapshots[@]}"
    for subvol in "${failed_snapshots[@]}"; do
        echo "  ✗ $subvol"
    done
    exit 1
else
    echo "All snapshots completed successfully!"
fi

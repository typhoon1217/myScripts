#!/bin/zsh

# Local snapshot creation script for Btrfs
# Run as root (e.g., with sudo)

# Configuration
SOURCE_ROOT="/"                      # Root filesystem to snapshot
SNAPSHOT_DIR="/snapshots"            # Directory for snapshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)     # Unique timestamp for snapshots
SUBVOLS=("@" "@home")                # Subvolumes to snapshot (adjust as needed)
KEEP_SNAPS=5                         # Number of snapshots to keep locally

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Create snapshot directory if it doesn’t exist
mkdir -p "$SNAPSHOT_DIR" || {
    echo "Failed to create snapshot directory at $SNAPSHOT_DIR."
    exit 1
}

# Function to clean up old snapshots
cleanup_snapshots() {
    local dir="$1"
    local prefix="$2"
    local keep="$3"
    ls -d "$dir/$prefix"* 2>/dev/null | sort -r | tail -n +$((keep + 1)) | while read -r snap; do
        btrfs subvolume delete "$snap" && echo "Deleted old snapshot: $snap"
    done
}

# Main snapshot loop for each subvolume
for subvol in "${SUBVOLS[@]}"; do
    echo "Creating snapshot for subvolume: $subvol"

    # Define snapshot path
    SNAPSHOT_PATH="$SNAPSHOT_DIR/$subvol-$TIMESTAMP"

    # Create a read-only snapshot
    btrfs subvolume snapshot -r "$SOURCE_ROOT" "$SNAPSHOT_PATH" || {
        echo "Failed to create snapshot for $subvol."
        exit 1
    }
    sync  # Ensure snapshot is written
    echo "Snapshot created: $SNAPSHOT_PATH"

    # Clean up old snapshots locally
    cleanup_snapshots "$SNAPSHOT_DIR" "$subvol-" "$KEEP_SNAPS"
done

echo "Local snapshots completed successfully at $(date)."

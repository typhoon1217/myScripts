#!/bin/zsh

# Full system backup script using rsync with Btrfs compression
# Run as root (e.g., with sudo)

# Configuration
BACKUP_MOUNT="/mnt/backup"
SOURCE_ROOT="/"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_MOUNT/full-backup-$TIMESTAMP"
KEEP_BACKUPS=2

# Enable debugging
set -x

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Check if backup drive is mounted
if ! mountpoint -q "$BACKUP_MOUNT"; then
    echo "Backup drive not mounted at $BACKUP_MOUNT. Please mount it and try again."
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR" || {
    echo "Failed to create backup directory at $BACKUP_DIR."
    exit 1
}

# Function to clean up old backups
cleanup_backups() {
    local dir="$1"
    local prefix="$2"
    local keep="$3"
    local backups=($(ls -d "$dir/$prefix"* 2>/dev/null | sort -r))
    local count=${#backups[@]}
    if (( count > keep )); then
        for (( i = keep; i < count; i++ )); do
            rm -rf "${backups[$i]}" && echo "Deleted old backup: ${backups[$i]}"
        done
    fi
}

# Perform full backup with rsync
echo "Starting full system backup to $BACKUP_DIR..."
rsync -aAX --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/snapshots/*"} "$SOURCE_ROOT" "$BACKUP_DIR" || {
    echo "Full backup failed."
    rm -rf "$BACKUP_DIR"
    exit 1
}
echo "Full backup completed to $BACKUP_DIR."

# Clean up old backups
cleanup_backups "$BACKUP_MOUNT" "full-backup-" "$KEEP_BACKUPS"

echo "Full backup completed successfully at $(date)."
set +x

#!/bin/bash

# Setup script for zenity-askpass to work with shared zshrc configuration
# This script creates the zenity-askpass helper for GUI sudo prompts

set -e

SCRIPT_PATH="/usr/local/bin/zenity-askpass"
BACKUP_PATH="/usr/local/bin/zenity-askpass.bak"

echo "=== Zenity Askpass Setup Script ==="
echo "This script will install zenity-askpass for GUI sudo prompts"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "Don't run this script as root. It will use su when needed."
    exit 1
fi

# Check if zenity is installed
if ! command -v zenity &> /dev/null; then
    echo "Error: zenity is not installed!"
    echo "Please install it first: sudo pacman -S zenity"
    echo "Or run: su -c 'pacman -S zenity'"
    exit 1
fi

# Check if script already exists
if [[ -f "$SCRIPT_PATH" ]]; then
    echo "Zenity-askpass already exists at $SCRIPT_PATH"
    echo "Creating backup and replacing..."
    su -c "cp '$SCRIPT_PATH' '$BACKUP_PATH'" || {
        echo "Failed to create backup. Exiting."
        exit 1
    }
fi

# Create the zenity-askpass script
echo "Creating zenity-askpass script..."
su -c 'cat > /usr/local/bin/zenity-askpass << "EOF"
#!/bin/bash
# Zenity askpass helper for sudo GUI prompts with proper output handling
password=$(zenity --password --title="sudo password" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$password" ]; then
    echo "$password"
    exit 0
else
    exit 1
fi
EOF' || {
    echo "Failed to create zenity-askpass script"
    exit 1
}

# Make it executable
echo "Making script executable..."
su -c "chmod +x '$SCRIPT_PATH'" || {
    echo "Failed to make script executable"
    exit 1
}

# Verify the script works
echo "Testing zenity-askpass script..."
if [[ -x "$SCRIPT_PATH" ]]; then
    echo "✓ Script created successfully at $SCRIPT_PATH"
else
    echo "✗ Script creation failed"
    exit 1
fi

# zshrc configuration is handled separately (synced across devices)

echo "=== Setup Complete ==="
echo "Zenity-askpass has been installed to: $SCRIPT_PATH"
echo ""
echo "To test, open a new terminal and run: sudo whoami"
echo "You should see a GUI password prompt."
echo ""
echo "If you need to remove this setup:"
echo "  su -c 'rm $SCRIPT_PATH'"

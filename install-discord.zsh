#!/bin/bash

# Define the download directory and filename pattern.
DOWNLOAD_DIR="$HOME/Downloads"
FILENAME_PATTERN="discord-*.tar.gz"
DISCORD_DIR="Discord"

# Find the latest Discord tar.gz file.
DISCORD_FILENAME="$HOME/Downloads/discord-0.0.90.tar.gz"


# Check if a file was found.
if [ -z "$DISCORD_FILENAME" ]; then
  echo "Error: Discord tar.gz file not found in $DOWNLOAD_DIR."
  exit 1
fi

# Extract the tar.gz archive.
mkdir -p "$DISCORD_DIR"
tar -xzf "$DISCORD_FILENAME" -C "$DISCORD_DIR"

# Check if extraction was successful.
if [ $? -ne 0 ]; then
  echo "Error extracting Discord."
  exit 1
fi

# Create a desktop entry (optional, but convenient).
cat <<EOF > ~/.local/share/applications/discord.desktop
[Desktop Entry]
Name=Discord
Comment=Chat with your friends and communities.
Exec=$HOME/$DISCORD_DIR/Discord
Icon=$HOME/$DISCORD_DIR/discord.png
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
StartupWMClass=discord
EOF

# Make the desktop entry executable.
chmod +x ~/.local/share/applications/discord.desktop

echo "Discord installed successfully!"
echo "You can launch it from your application menu or by running '$HOME/$DISCORD_DIR/Discord'."

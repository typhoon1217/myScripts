#!/bin/zsh

# Script to cleanly reinstall Cursor IDE on Arch Linux

# Variables
PACKAGE_NAME="cursor-bin" # Cursor IDE package name in AUR
APPIMAGE_URL="<YOUR_CURSOR_APPIMAGE_URL>" # Replace with the actual URL if using AppImage

# Function to uninstall Cursor IDE
uninstall_cursor() {
  echo "Uninstalling Cursor IDE..."
  if command -v yay &> /dev/null; then
    yay -Rns "$PACKAGE_NAME"
  else
    echo "yay not found. If Cursor was installed via appimage, please remove the appimage manually, and any desktop files."
  fi
  rm -rf ~/.cursor ~/.config/Cursor ~/.cache/cursor-updater
  echo "Cursor IDE uninstalled."
}

# Function to install Cursor IDE from AUR
install_cursor_aur() {
  echo "Installing Cursor IDE from AUR..."
  if command -v yay &> /dev/null; then
    yay -S "$PACKAGE_NAME" -y
  else
    echo "yay not found. Cannot install from AUR."
  fi
}

#Function to install cursor from appimage
install_cursor_appimage() {
  echo "Installing Cursor IDE from AppImage..."
  if [[ -z "$APPIMAGE_URL" ]]; then
    echo "Error: APPIMAGE_URL is not set. Please set the APPIMAGE_URL variable in the script."
    return 1
  fi

  local appimage_filename=$(basename "$APPIMAGE_URL")

  # Download the AppImage
  echo "Downloading AppImage..."
  curl -L -o "$appimage_filename" "$APPIMAGE_URL"

  if [[ $? -ne 0 ]]; then
      echo "Error downloading appimage"
      return 1
  fi

  # Make the AppImage executable
  echo "Making AppImage executable..."
  chmod +x "$appimage_filename"

  echo "Cursor IDE AppImage installed as $appimage_filename. You can run it directly."
  echo "You will have to create a .desktop file manually if you want a menu entry."

}

# Main script logic
echo "Choose installation method:"
echo "1. Uninstall and reinstall from AUR (using cursor-bin)"
echo "2. Uninstall and install from AppImage"
echo "3. Only uninstall"
read -r choice

case "$choice" in
  1)
    uninstall_cursor
    install_cursor_aur
    ;;
  2)
    uninstall_cursor
    install_cursor_appimage
    ;;
  3)
    uninstall_cursor
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

echo "Process completed."

#!/bin/bash
# Force ALL Electron apps to use native Wayland
# ~/bin/force-wayland-electron.sh

WAYLAND_FLAGS="--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime"

echo "=== Force All Electron Apps to Wayland ==="
echo "This will modify ALL desktop files to use native Wayland"
echo

# Known Electron apps and common apps that should use Wayland
ELECTRON_KEYWORDS=("electron" "chromium" "chrome" "code" "teams" "discord" "slack" "spotify" "signal" "telegram" "whatsapp" "zoom" "obs" "figma" "notion" "typora")

# Create local applications directory
mkdir -p "$HOME/.local/share/applications"

echo "Scanning /usr/share/applications/ for potential Electron apps..."
echo

processed=0

for desktop_file in /usr/share/applications/*.desktop; do
    if [ ! -f "$desktop_file" ]; then
        continue
    fi
    
    basename_file=$(basename "$desktop_file" .desktop)
    
    # Check if it's likely an Electron app
    is_electron=false
    
    # Check filename against known Electron apps
    for keyword in "${ELECTRON_KEYWORDS[@]}"; do
        if [[ "$basename_file" == *"$keyword"* ]]; then
            is_electron=true
            break
        fi
    done
    
    # Also check file content for Electron indicators
    if [ "$is_electron" = false ]; then
        if grep -qi "electron\|chromium\|--enable-features\|--ozone-platform" "$desktop_file"; then
            is_electron=true
        fi
    fi
    
    if [ "$is_electron" = true ]; then
        echo "Processing: $basename_file"
        
        local_file="$HOME/.local/share/applications/$basename_file.desktop"
        
        # Copy to local directory
        if cp "$desktop_file" "$local_file"; then
            # Modify ALL Exec lines to force Wayland
            sed -i "/^Exec=/ {
                # Don't add flags if they already exist
                /--ozone-platform=wayland/! {
                    # Add flags before any % parameters
                    s| %| $WAYLAND_FLAGS %|
                    # If no % parameters, add at end
                    /% /! s|$| $WAYLAND_FLAGS|
                }
            }" "$local_file"
            
            # Verify flags were added
            if grep -q -- "--ozone-platform=wayland" "$local_file"; then
                echo "  ✓ Successfully forced Wayland for $basename_file"
                ((processed++))
            else
                echo "  ⚠ May need manual adjustment for $basename_file"
                echo "    File: $local_file"
            fi
        else
            echo "  ✗ Failed to copy $basename_file"
        fi
    fi
done

echo
echo "=== Summary ==="
echo "Processed $processed applications"
echo "All modified desktop files are in: $HOME/.local/share/applications/"
echo
echo "To test if apps are using Wayland:"
echo "1. Launch an app"
echo "2. Run: xeyes"
echo "3. If xeyes doesn't track the app window = native Wayland ✓"
echo "4. If xeyes tracks the app window = XWayland (needs fixing)"
echo
echo "To undo all changes:"
echo "  rm ~/.local/share/applications/*.desktop"

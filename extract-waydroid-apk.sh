#!/usr/bin/env zsh

# waydroid_apk_extractor.sh
# Script to extract APKs from Waydroid apps to Documents/apks directory

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges to access Waydroid data."
    echo "Please run with sudo."
    exit 1
fi

# Check if Waydroid is installed
if ! command -v waydroid &> /dev/null; then
    echo "Waydroid is not installed. Please install it first."
    exit 1
fi

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo "Warning: adb is not installed. Some functionality may be limited."
    echo "Consider installing it with: sudo pacman -S android-tools"
fi

# Check dependencies
if ! command -v fzf &> /dev/null; then
    echo "fzf is not installed. It's needed for app selection."
    echo "Install it with: sudo pacman -S fzf"
    exit 1
fi

# --- FIX START ---
# Get the real user's home directory, even when running with sudo
# This ensures the output goes to the invoking user's Documents/apks
REAL_USER=$(logname)
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Create output directory if it doesn't exist
OUTPUT_DIR="$REAL_HOME/Documents/apks"
# --- FIX END ---

mkdir -p "$OUTPUT_DIR"

# Check if Waydroid is running and force start the session
echo "Making sure Waydroid session is started..."
waydroid session start &>/dev/null
sleep 5

# Get the list of installed apps from Waydroid using adb
echo "Fetching list of installed apps from Waydroid..."
TEMP_APP_LIST=$(mktemp)

# Make sure adb connection to Waydroid is established
waydroid prop set waydroid.adb_enabled true &>/dev/null
adb connect 192.168.240.112 &>/dev/null

# Get the app list using adb
adb shell pm list packages > "$TEMP_APP_LIST"

# If no apps found
if ! grep -q "package:" "$TEMP_APP_LIST"; then
    echo "No apps found in Waydroid. This could be because:"
    echo "1. Waydroid is not properly initialized"
    echo "2. ADB connection failed"
    echo "3. No apps are installed"
    echo
    echo "Trying alternative method..."
    
    # Alternative method: check directly in the Waydroid data folder
    WAYDROID_APPS_DIR="/var/lib/waydroid/data/app"
    if [ -d "$WAYDROID_APPS_DIR" ]; then
        ls -1 "$WAYDROID_APPS_DIR" > "$TEMP_APP_LIST"
        if [ -s "$TEMP_APP_LIST" ]; then
            echo "Found apps using directory method."
        else
            echo "No apps found in Waydroid directory either."
            rm "$TEMP_APP_LIST"
            exit 1
        fi
    else
        echo "Waydroid app directory not found. Make sure Waydroid is properly set up."
        rm "$TEMP_APP_LIST"
        exit 1
    fi
fi

# Extract app packages from the list and create a selection menu
if grep -q "package:" "$TEMP_APP_LIST"; then
    # Extract app packages and filter out all com.android.* apps but keep Google apps
    APPS=$(grep "package:" "$TEMP_APP_LIST" | sed -E 's/package:(.*)/\1/' | 
            grep -v -E '^(android\.|com\.android\.|org\.lineageos\.|lineageos\.)' | 
            sort)
else
    # If using directory method, just use the directory names and filter
    APPS=$(cat "$TEMP_APP_LIST" | 
            grep -v -E '^(android\.|com\.android\.|org\.lineageos\.|lineageos\.)' | 
            sort)
fi

# Check if we have any apps after filtering
if [[ -z "$APPS" ]]; then
    echo "No apps found in Waydroid after filtering out system apps."
    echo "If you need system apps as well, edit the script to remove the filtering."
    rm "$TEMP_APP_LIST"
    exit 1
fi

rm "$TEMP_APP_LIST"

# Create a selection menu with clear instructions
echo -e "\n\033[1;36m=========================================================\033[0m"
echo -e "\033[1;33mAPP SELECTION MENU INSTRUCTIONS:\033[0m"
echo -e "\033[1m- Use UP/DOWN arrow keys to navigate\033[0m"
echo -e "\033[1m- Type to search for specific apps\033[0m"
echo -e "\033[1;32m- Press TAB to select/deselect an app\033[0m"
echo -e "\033[1;32m  (Selected apps will have >> markers)\033[0m"
echo -e "\033[1;34m- Press ENTER to confirm and extract selected apps\033[0m"
echo -e "\033[1;31m- Press ESC to cancel\033[0m"
echo -e "\033[1;36m=========================================================\033[0m"
echo -e "\033[1mSearching and selecting are separate actions:\033[0m"
echo -e "1. Type to narrow down the list"
echo -e "2. Use TAB to mark items for selection\n"

# Use fzf with very basic options and TAB for selection instead of SPACE
SELECTED_APPS=$(echo "$APPS" | fzf \
  --multi \
  --cycle \
  --no-mouse \
  --bind=tab:toggle+up \
  --border \
  --header="USE TAB TO SELECT/DESELECT (not space) | ENTER to confirm" \
  --prompt="Search: " \
  --marker=">>" \
  --pointer=">" \
  --color=marker:green)

if [[ -z "$SELECTED_APPS" ]]; then
    echo "No apps selected. Exiting."
    exit 0
fi

# Process each selected app
echo "Extracting selected APKs..."
echo "$SELECTED_APPS" | while read -r PACKAGE; do
    echo "Processing $PACKAGE..."
    
    # Create a subdirectory for the app's APKs
    APP_DIR="$OUTPUT_DIR/${PACKAGE}"
    mkdir -p "$APP_DIR"
    
    # Method 1: Using adb to pull the APK
    APK_FOUND=false
    
    # Try to get the paths using adb
    if command -v adb &> /dev/null; then
        echo "Trying ADB method..."
        
        # Get all APK paths for this package (base + split APKs)
        APK_PATHS=$(adb shell pm path "$PACKAGE" 2>/dev/null)
        
        if [[ ! -z "$APK_PATHS" ]]; then
            echo "Found APKs via ADB for $PACKAGE"
            
            # Process each APK path
            echo "$APK_PATHS" | while read -r PATH_LINE; do
                # Extract the actual path from the line (remove "package:")
                APK_PATH=$(echo "$PATH_LINE" | sed -E 's/package:(.*)/\1/')
                
                # Extract filename from path for better organization
                APK_FILENAME=$(basename "$APK_PATH")
                OUTPUT_FILE="$APP_DIR/$APK_FILENAME"
                
                echo "Pulling $APK_FILENAME..."
                adb pull "$APK_PATH" "$OUTPUT_FILE" &>/dev/null
                
                if [[ -f "$OUTPUT_FILE" ]]; then
                    chown "$REAL_USER":"$(id -gn "$REAL_USER")" "$OUTPUT_FILE"
                    echo "Extracted $APK_FILENAME to $OUTPUT_FILE"
                    APK_FOUND=true
                else
                    echo "Failed to pull $APK_FILENAME"
                fi
            done
        fi
    fi
    
    # Method 2: Direct file system access (only if ADB method failed or no APKs found via ADB)
    # Check if any APKs were found in the APP_DIR from the ADB method. If not, try direct access.
    if ! find "$APP_DIR" -maxdepth 1 -name "*.apk" -print -quit | grep -q .; then
        echo "Trying direct file system access..."
        
        # Check in app directory first
        WAYDROID_DATA_PATH="/var/lib/waydroid/data/data"
        WAYDROID_APP_PATH="/var/lib/waydroid/data/app"
        
        POTENTIAL_DIRS=(
            "$WAYDROID_APP_PATH"
            "$WAYDROID_DATA_PATH/app"
        )
        
        for BASE_DIR in "${POTENTIAL_DIRS[@]}"; do
            if [[ -d "$BASE_DIR" ]]; then
                # Look for directories that might contain this package's APKs
                PACKAGE_DIRS=$(find "$BASE_DIR" -type d -name "*$PACKAGE*" 2>/dev/null)
                
                if [[ ! -z "$PACKAGE_DIRS" ]]; then
                    echo "Found potential package directories:"
                    
                    echo "$PACKAGE_DIRS" | while read -r PKG_DIR; do
                        echo "Checking $PKG_DIR for APKs..."
                        
                        # Find all APK files in this directory
                        APK_FILES=$(find "$PKG_DIR" -name "*.apk" 2>/dev/null)
                        
                        if [[ ! -z "$APK_FILES" ]]; then
                            echo "$APK_FILES" | while read -r APK_FILE; do
                                APK_FILENAME=$(basename "$APK_FILE")
                                OUTPUT_FILE="$APP_DIR/$APK_FILENAME"
                                
                                echo "Copying $APK_FILENAME..."
                                cp "$APK_FILE" "$OUTPUT_FILE"
                                chown "$REAL_USER":"$(id -gn "$REAL_USER")" "$OUTPUT_FILE"
                                echo "Extracted $APK_FILENAME to $OUTPUT_FILE"
                                APK_FOUND=true
                            done
                        fi
                    done
                fi
            fi
        done
    fi
    
    # Report if APK not found after both methods
    if ! find "$APP_DIR" -maxdepth 1 -name "*.apk" -print -quit | grep -q .; then
        echo "Could not find any APKs for $PACKAGE. Tried ADB and direct file access methods."
    else
        # Create a combined APK for convenience
        echo "Creating a combined APK file..."
        COMBINED_APK="$OUTPUT_DIR/${PACKAGE}.apk"
        # Use cat to combine multiple APKs if they exist, or just copy the first one
        # This handles cases where an app might have multiple split APKs
        if ls "$APP_DIR"/*.apk &>/dev/null; then
            cat "$APP_DIR"/*.apk > "$COMBINED_APK" 2>/dev/null
            if [[ -f "$COMBINED_APK" ]]; then
                chown "$REAL_USER":"$(id -gn "$REAL_USER")" "$COMBINED_APK"
                echo "Created combined APK at $COMBINED_APK"
            fi
        fi
    fi
done

echo "Done! APKs have been extracted to $OUTPUT_DIR"


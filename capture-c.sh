#!/bin/bash

# --- Configuration ---
# Default directory to save screenshots
# You can change this to any directory you prefer, e.g., "$HOME/Screenshots"
SAVE_DIR="$HOME/Pictures/Screenshots/"

# Default filename prefix
FILENAME_PREFIX="screenshot-crop"

# Default action after capture: 'save', 'copy', 'edit' (with swappy)
# If 'edit' is chosen, it will save the image after editing with swappy.
DEFAULT_ACTION="save"

# --- Create Save Directory if it doesn't exist ---
mkdir -p "$SAVE_DIR"

# --- Function to display help message ---
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Capture a cropped screenshot using grim and slurp."
    echo ""
    echo "Options:"
    echo "  -s, --save       Save the screenshot to a file (default action if no other action specified)."
    echo "  -c, --copy       Copy the screenshot to the clipboard (requires wl-clipboard)."
    echo "  -e, --edit       Edit the screenshot with swappy, then save/copy from swappy (requires swappy)."
    echo "                   If -e is used, -s and -c are ignored as swappy handles saving/copying."
    echo "  -d <dir>         Specify a custom save directory (e.g., -d ~/Documents/Snaps)."
    echo "  -p <prefix>      Specify a custom filename prefix (e.g., -p my-project-snap)."
    echo "  -h, --help       Display this help message and exit."
    echo ""
    echo "Example:"
    echo "  $(basename "$0") -s                     # Capture and save to default location"
    echo "  $(basename "$0") -c                     # Capture and copy to clipboard"
    echo "  $(basename "$0") -e                     # Capture, open in swappy, then save/copy from swappy"
    echo "  $(basename "$0") -s -d ~/Desktop -p my-crop # Capture, save to ~/Desktop with 'my-crop' prefix"
    echo ""
}

# --- Parse Command Line Arguments ---
ACTION="$DEFAULT_ACTION"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -s|--save)
            ACTION="save"
            ;;
        -c|--copy)
            ACTION="copy"
            ;;
        -e|--edit)
            ACTION="edit"
            ;;
        -d)
            if [ -n "$2" ]; then
                SAVE_DIR="$2"
                shift
            else
                echo "Error: -d requires a directory path." >&2
                exit 1
            fi
            ;;
        -p)
            if [ -n "$2" ]; then
                FILENAME_PREFIX="$2"
                shift
            else
                echo "Error: -p requires a filename prefix." >&2
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
    esac
    shift
done

# --- Check for dependencies ---
# slurp and grim are always required
if ! command -v slurp &> /dev/null; then
    echo "Error: 'slurp' not found. Please install it (e.g., sudo pacman -S slurp)." >&2
    exit 1
fi
if ! command -v grim &> /dev/null; then
    echo "Error: 'grim' not found. Please install it (e.g., sudo pacman -S grim)." >&2
    exit 1
fi

# Check for wl-clipboard if copy action is requested
if [ "$ACTION" = "copy" ]; then
    if ! command -v wl-copy &> /dev/null; then
        echo "Error: 'wl-clipboard' not found. Please install it (e.g., sudo pacman -S wl-clipboard)." >&2
        exit 1
    fi
fi

# Check for swappy if edit action is requested
if [ "$ACTION" = "edit" ]; then
    if ! command -v swappy &> /dev/null; then
        echo "Error: 'swappy' not found. Please install it (e.g., sudo pacman -S swappy)." >&2
        exit 1
    fi
fi

# --- Capture Logic ---
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
FILENAME="${FILENAME_PREFIX}-${TIMESTAMP}.png"
FILE_PATH="${SAVE_DIR}/${FILENAME}"

# Use slurp to get the selection geometry
GEOMETRY=$(slurp)

if [ -z "$GEOMETRY" ]; then
    echo "Screenshot selection cancelled."
    exit 0
fi

case "$ACTION" in
    save)
        grim -g "$GEOMETRY" "$FILE_PATH"
        if [ $? -eq 0 ]; then
            echo "Screenshot saved to: $FILE_PATH"
        else
            echo "Error: Failed to save screenshot." >&2
            exit 1
        fi
        ;;
    copy)
        grim -g "$GEOMETRY" - | wl-copy
        if [ $? -eq 0 ]; then
            echo "Screenshot copied to clipboard."
            # Optional: Add a notification if you have 'dunstify' or 'notify-send'
            # notify-send "Screenshot" "Cropped screenshot copied to clipboard!"
        else
            echo "Error: Failed to copy screenshot to clipboard." >&2
            exit 1
        fi
        ;;
    edit)
        # grim captures to stdout, swappy takes stdin, then handles saving/copying
        grim -g "$GEOMETRY" - | swappy -f "$FILE_PATH"
        if [ $? -eq 0 ]; then
            echo "Screenshot opened in Swappy. Saved to $FILE_PATH after editing (if saved)."
        else
            echo "Error: Failed to open screenshot in Swappy." >&2
            exit 1
        fi
        ;;
    *)
        echo "Error: Invalid action '$ACTION'. This should not happen." >&2
        exit 1
        ;;
esac

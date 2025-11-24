#!/usr/bin/bash
# File: ~/bin/phone
# → chmod +x ~/bin/phone   (only once)
# → then just type: phone   (anywhere)

CONFIG_DIR="$HOME/.config/scrcpy-wireless"
mkdir -p "$CONFIG_DIR"
LAST_IP_FILE="$CONFIG_DIR/last_ip.txt"

# Try to read last used IP
if [[ -f "$LAST_IP_FILE" ]]; then
    DEFAULT_IP=$(cat "$LAST_IP_FILE")
else
    DEFAULT_IP="172.30.1.10"   # change this to your usual subnet if you want
fi

clear
echo "╔══════════════════════════════════════════════════╗"
echo "║          Wireless Android → Arch Linux           ║"
echo "║              (scrcpy + adb wireless)             ║"
echo "╚══════════════════════════════════════════════════╝"
echo
echo "Last used IP: $DEFAULT_IP"
echo
echo "Choose connection method:"
echo "   1) Type IP:port manually"
echo "   2) Scan QR code (easiest!)"
echo "   3) Just press Enter to try last IP with current wireless debugging port"
echo

read -p " → Choose (1/2/3 or Enter for auto): " choice
echo

case "$choice" in
    2)
        echo "Opening QR scanner… (install 'zbar-tools' if it fails)"
        echo "Point your terminal camera / webcam at the Wireless debugging QR code"
        read -p "Press Enter when ready…" 
        QR=$(zbarcam --raw -q || echo "failed")
        if [[ $QR == failed ]]; then
            echo "QR scan failed. Install zbar with: sudo pacman -S zbar"
            echo "Falling back to manual entry…"
            sleep 2
        else
            # QR format: WIFI:S:ADB;T:pairing_code;P:123456;;
            IP_PORT=$(echo "$QR" | grep -oE '172\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+')
            echo "QR detected → $IP_PORT"
        fi
        ;;

    3|"")
        echo "Trying to auto-detect current wireless debugging port on $DEFAULT_IP…"
        # This trick works on Android 11–15: ask the phone itself what port it's listening on
        CURRENT_PORT=$(adb -s "${DEFAULT_IP}:36543" shell 'getprop service.adb.tcp.port' 2>/dev/null | tr -d '\r')
        if [[ -n "$CURRENT_PORT" && "$CURRENT_PORT" != "-1" ]]; then
            IP_PORT="${DEFAULT_IP}:${CURRENT_PORT}"
            echo "Auto-detected → $IP_PORT"
        else
            echo "Auto-detect failed. Falling back to manual…"
            sleep 1
        fi
        ;;
esac

# Manual entry fallback / override
if [[ -z "$IP_PORT" ]]; then
    read -p "Enter IP:port (e.g. 172.30.1.10:37109): " manual
    IP_PORT="$manual"
fi

# Validate format
if ! [[ $IP_PORT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
    echo "Invalid format!"
    exit 1
fi

# Save IP for next time
echo "$IP_PORT" | cut -d: -f1 > "$LAST_IP_FILE"

echo
echo "Connecting to $IP_PORT …"
adb connect "$IP_PORT" && echo "Connected!" || echo "Already connected / minor warning is fine"

echo
echo "Starting scrcpy…"
echo "(Close the window or press Ctrl+C to stop)"
echo
scrcpy -s "$IP_PORT" --turn-screen-off --stay-awake

echo
echo "Done. Run 'phone' again anytime!"

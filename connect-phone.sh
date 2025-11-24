# ~/bin/adb-connect-phone  (make it executable with chmod +x)
#!/bin/bash
IP="172.30.1.10"   # change only if your phone IP changes

# Find the current wireless debugging port automatically
PORT=$(adb -s $IP:36543 shell ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | cut -d: -f2)
if [ -z "$PORT" ]; then
    echo "Phone not reachable or wireless debugging off"
    exit 1
fi

echo "Connecting to $IP:$PORT ..."
adb connect $IP:$PORT && scrcpy

#!/bin/bash

# Fetch timezone using ipapi.co
TIMEZONE=$(curl --fail --silent https://ipapi.co/timezone)

if [ -z "$TIMEZONE" ]; then
    echo "Failed to retrieve timezone from ipapi.co. Check internet connection or API availability."
    exit 1
fi

echo "Detected timezone: $TIMEZONE"

# Set the timezone
sudo timedatectl set-timezone "$TIMEZONE"

if [ $? -eq 0 ]; then
    echo "Timezone successfully set to $TIMEZONE."
else
    echo "Failed to set timezone. You may need to run 'timedatectl list-timezones' to verify the timezone string."
fi

# Verify
timedatectl

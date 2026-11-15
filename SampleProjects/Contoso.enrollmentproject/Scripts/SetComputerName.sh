#!/bin/bash
# Sample enrollment script for Enrollment Bundle Studio.
# Sets the computer name to CONTOSO-<serial number>. Runs as root on the device.
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin"

serial=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/ {print $4}')
if [ -z "$serial" ]; then
    echo "Could not read the serial number." >&2
    exit 1
fi

name="CONTOSO-${serial}"
for key in ComputerName HostName LocalHostName; do
    if ! scutil --set "$key" "$name"; then
        echo "Failed to set $key." >&2
        exit 1
    fi
done

echo "Computer name set to $name."
exit 0

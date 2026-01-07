#!/bin/bash
# Monitor notarization status and kill the loop script when approved

get_latest_status() {
    xcrun notarytool history --keychain-profile "notarytool" 2>/dev/null | grep -A3 "createdDate:" | head -4 | grep "status:" | awk '{print $2}'
}

get_latest_id() {
    xcrun notarytool history --keychain-profile "notarytool" 2>/dev/null | grep -A1 "createdDate:" | head -2 | grep "id:" | awk '{print $2}'
}

echo "Monitoring notarization status..."
echo "Checking most recent submission every 30 seconds."
echo ""

while true; do
    STATUS=$(get_latest_status)
    ID=$(get_latest_id)

    echo "$(date '+%H:%M:%S') - Latest: $ID = $STATUS"

    if [ "$STATUS" = "Accepted" ]; then
        echo ""
        echo "=========================================="
        echo "SUCCESS! Notarization approved!"
        echo "=========================================="
        echo "Approved ID: $ID"

        # Kill the loop script
        pkill -f "notarize-loop.sh" 2>/dev/null && echo "Stopped notarize-loop.sh"

        # Staple the ticket
        echo ""
        echo "Stapling notarization ticket..."
        xcrun stapler staple VoiceWrite.app

        echo ""
        echo "Done! VoiceWrite.app is now notarized."
        exit 0
    fi

    if [ "$STATUS" = "Invalid" ]; then
        echo "WARNING: Latest submission is Invalid. Check logs with:"
        echo "  xcrun notarytool log $ID --keychain-profile notarytool"
    fi

    sleep 30
done

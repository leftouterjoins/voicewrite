#!/bin/bash
# Build once, then submit to notarization as fast as possible

set -e

echo "Building once..."
make app
rm -f VoiceWrite-notarize.zip
ditto -c -k --keepParent VoiceWrite.app VoiceWrite-notarize.zip
echo "Build complete. Starting rapid submissions..."
echo ""

COUNT=0
while true; do
    COUNT=$((COUNT + 1))
    echo "=== Submission #$COUNT $(date '+%H:%M:%S') ==="
    xcrun notarytool submit VoiceWrite-notarize.zip --keychain-profile "notarytool"
    echo ""
    sleep 5
done

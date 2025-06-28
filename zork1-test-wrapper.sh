#!/bin/sh
# Fixed wrapper for Zork I - gets username from parameter

# Get username from command line (dgamelaunch passes it as %n)
USER_NAME="$1"

# If no username provided, we have a problem
if [ -z "$USER_NAME" ]; then
    echo "ERROR: No username provided to wrapper!"
    echo "Press Enter to continue..."
    read dummy
    exit 1
fi

# Base directories
TEST_DIR="${DGAMELAUNCH_TEST_DIR:-/tmp/dgl-test}"
ZORK_BASE="/usr/games/lib/zork1"

# Get first character of username for directory structure
USER_FIRST=$(printf %.1s "$USER_NAME")
USER_BASE="${TEST_DIR}/userdata/${USER_FIRST}/${USER_NAME}/zork"

# Create user directory if needed
mkdir -p "${USER_BASE}"

# Copy game file to user directory if not there
if [ ! -f "${USER_BASE}/Zork1.dat" ]; then
    cp "${ZORK_BASE}/Zork1.dat" "${USER_BASE}/"
fi

# Change to user directory
cd "${USER_BASE}" || {
    echo "ERROR: Cannot change to user directory!"
    exit 1
}

# Show save information if any saves exist
# List all files except the game file itself
SAVES=$(ls -1 2>/dev/null | grep -v "^Zork1.dat$")
if [ -n "$SAVES" ]; then
    echo "=================================================================================="
    echo "Your saved games:"
    echo "$SAVES" | while read save; do
        echo "  $save"
    done
    echo ""
    echo "To load a save: Type RESTORE, then enter the filename"
    echo "To start fresh: Type RESTART"
    echo "=================================================================================="
    echo ""
    sleep 2
fi

# Run dfrotz
exec dfrotz -q -w 80 -R . "./Zork1.dat"
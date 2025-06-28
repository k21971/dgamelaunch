#!/bin/sh
# Wrapper script for running Zork I in dgamelaunch
# This handles per-user save directories and frotz options

# Get username from environment
# dgamelaunch passes the username when launching games
USER_NAME="${DGL_USER:-${USER:-unknown}}"

# Base directories
ZORK_BASE="/usr/games/lib/zork1"
USER_BASE="/dgldir/userdata/${USER_NAME}/zork"

# Create user directory if it doesn't exist
if [ ! -d "${USER_BASE}" ]; then
    mkdir -p "${USER_BASE}"
fi

# Change to user directory for saves
cd "${USER_BASE}" || exit 1

# Run dfrotz with appropriate options:
# -q: Quiet mode (suppress header)
# -w 80: Screen width
# -R: Restrict file operations to user directory
exec /bin/dfrotz -q -w 80 -R "${USER_BASE}" "${ZORK_BASE}/Zork1.dat"
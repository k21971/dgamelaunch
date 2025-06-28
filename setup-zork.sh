#!/bin/bash
# Setup script for adding Zork I to dgamelaunch

set -e  # Exit on error

echo "=== dgamelaunch Zork I Setup Script ==="
echo

# Check if running as root (needed for chroot setup)
if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run as root for chroot setup."
    echo "Usage: sudo $0"
    exit 1
fi

# Configuration
CHROOT_PATH="/opt/nethack/nethack.alt.org"
ZORK_SOURCE="/usr/games/lib/zork1/Zork1.dat"
WRAPPER_SCRIPT="zork1-wrapper.sh"

echo "1. Checking prerequisites..."

# Check if frotz is installed
if ! command -v frotz &> /dev/null; then
    echo "ERROR: frotz is not installed. Please install it first:"
    echo "  sudo apt-get install frotz"
    exit 1
fi

# Check if Zork data file exists
if [ ! -f "$ZORK_SOURCE" ]; then
    echo "ERROR: Zork1.dat not found at $ZORK_SOURCE"
    exit 1
fi

# Check if wrapper script exists
if [ ! -f "$WRAPPER_SCRIPT" ]; then
    echo "ERROR: $WRAPPER_SCRIPT not found in current directory"
    exit 1
fi

echo "✓ Prerequisites checked"
echo

echo "2. Creating chroot directories..."

# Create necessary directories in chroot
mkdir -p "$CHROOT_PATH/zork"
mkdir -p "$CHROOT_PATH/bin"
mkdir -p "$CHROOT_PATH/dgldir/inprogress-zork1"

echo "✓ Directories created"
echo

echo "3. Copying files to chroot..."

# Copy Zork data file
cp -v "$ZORK_SOURCE" "$CHROOT_PATH/zork/Zork1.dat"
chmod 644 "$CHROOT_PATH/zork/Zork1.dat"

# Copy frotz binary
cp -v /usr/games/frotz "$CHROOT_PATH/bin/frotz"
chmod 755 "$CHROOT_PATH/bin/frotz"

# Copy wrapper script
cp -v "$WRAPPER_SCRIPT" "$CHROOT_PATH/bin/zork1-wrapper"
chmod 755 "$CHROOT_PATH/bin/zork1-wrapper"

echo "✓ Files copied"
echo

echo "4. Setting up shared libraries for frotz..."

# Create lib directories if they don't exist
mkdir -p "$CHROOT_PATH/lib"
mkdir -p "$CHROOT_PATH/lib64"

# Find and copy required libraries
echo "Copying required libraries..."
for lib in $(ldd /usr/games/frotz | grep -o '/lib[^ ]*' | sort -u); do
    if [ -f "$lib" ]; then
        cp -n "$lib" "$CHROOT_PATH$lib" 2>/dev/null || true
        echo "  Copied: $lib"
    fi
done

# Copy ld-linux if needed
if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
    cp -n /lib64/ld-linux-x86-64.so.2 "$CHROOT_PATH/lib64/" 2>/dev/null || true
fi

echo "✓ Libraries copied"
echo

echo "5. Creating sample banner files..."

# Create a simple banner for Zork menu option
cat > "$CHROOT_PATH/dgl-banner-zork" << 'EOF'
================================================================================
                    ZORK I: The Great Underground Empire
================================================================================

You are standing in an open field west of a white house, with a boarded front
door. There is a small mailbox here.

Save games are stored in your personal directory.
Use SAVE and RESTORE commands within the game.

================================================================================
EOF

echo "✓ Banner files created"
echo

echo "6. Configuration notes:"
echo
echo "To use Zork in dgamelaunch:"
echo "1. Use the provided dgamelaunch-zork.conf as a template"
echo "2. Add the Zork DEFINE block to your existing dgamelaunch.conf"
echo "3. Add menu entries for Zork (keys 'z' or '1' suggested)"
echo "4. Restart dgamelaunch"
echo
echo "The wrapper script handles:"
echo "- Per-user save directories"
echo "- Proper frotz options for terminal compatibility"
echo "- Security restrictions"
echo
echo "✓ Setup complete!"
echo
echo "Test with: dgamelaunch -c dgamelaunch-zork.conf"
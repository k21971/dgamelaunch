#!/bin/bash
# Setup script for building dgamelaunch for testing
# This script builds dgamelaunch with appropriate flags for testing

set -e  # Exit on error

echo "=== DGamelaunch Test Build Script ==="
echo ""

# Determine test directory
TEST_DIR="${DGAMELAUNCH_TEST_DIR:-/tmp/dgl-test}"
echo "Test directory: $TEST_DIR"

# Clean previous build
if [ "$1" != "--no-clean" ]; then
    echo "Cleaning previous build..."
    make clean 2>/dev/null || true
fi

# Configure options
CONFIG_PATH="$TEST_DIR/dgamelaunch.conf"
DB_PATH="$TEST_DIR/dgamelaunch.db"

# Check for SQLite support
if [ -f /usr/include/sqlite3.h ] && command -v sqlite3 >/dev/null 2>&1; then
    echo "Building with SQLite support..."
    SQLITE_OPTS="--enable-sqlite --with-sqlite-db=$DB_PATH"
    BUILD_TYPE="sqlite"
else
    echo "Building with flat file support (install libsqlite3-dev and sqlite3 for SQLite)"
    SQLITE_OPTS=""
    BUILD_TYPE="flatfile"
fi

# Configure and build
echo "Configuring dgamelaunch..."
CFLAGS="-g3 -O0 -Wall -Wextra -Wshadow -Wwrite-strings -Wformat=2 -Wformat-security -Wstrict-prototypes -Wmissing-prototypes" \
./autogen.sh --enable-shmem \
             --with-config-file="$CONFIG_PATH" \
             $SQLITE_OPTS

echo "Building dgamelaunch..."
make

# Build editors
echo "Building editors..."
make ee virus

echo ""
echo "=== Build Complete ==="
echo "Binary: ./dgamelaunch"
echo "Editors: ./ee ./virus"
echo "Build type: $BUILD_TYPE"
echo ""
echo "The test environment will be created when you run:"
echo "  ./test-dgamelaunch.sh"
echo ""
echo "This will create:"
echo "  - Test directory: $TEST_DIR"
echo "  - Config file: $CONFIG_PATH"
if [ "$BUILD_TYPE" = "sqlite" ]; then
    echo "  - SQLite database: $DB_PATH"
fi
echo ""
echo "And then launch dgamelaunch with the test menu where you can:"
echo "  - Register a new account"
echo "  - Play NetHack"
echo "  - Edit config files with ee or virus"
echo "  - Test all dgamelaunch features"
echo ""
echo "Next step: Run ./test-dgamelaunch.sh to test dgamelaunch"
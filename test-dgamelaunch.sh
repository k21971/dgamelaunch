#!/bin/bash
# Test script for dgamelaunch - works with both SQLite and flat file builds
# Usage: ./test-dgamelaunch.sh [--reset]

set -e  # Exit on error

# Check for terminal
if [ ! -t 0 ]; then
    echo "This script must be run in an interactive terminal!"
    exit 1
fi

# Configuration
TEST_DIR="${DGAMELAUNCH_TEST_DIR:-/tmp/dgl-test}"
NETHACK_PATH="${NETHACK_PATH:-/usr/games/lib/official_36_nethackdir}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine user to drop privileges to
if [ "$(id -u)" -eq 0 ]; then
    # If running as root, use the 'build' user (1001)
    SHED_UID=1001
    SHED_GID=1001
    echo "Running as root, will drop privileges to uid/gid 1001"
else
    # Use current user
    SHED_UID=$(id -u)
    SHED_GID=$(id -g)
fi

# Parse arguments
if [ "$1" = "--reset" ]; then
    echo "Resetting test environment..."
    rm -rf "$TEST_DIR"
fi

echo "=== DGamelaunch Test Environment ==="
echo "Test directory: $TEST_DIR"
echo "NetHack path: $NETHACK_PATH"
echo ""

# Check if dgamelaunch is built
if [ ! -f "$SCRIPT_DIR/dgamelaunch" ]; then
    echo "ERROR: dgamelaunch not found. Run ./setup-test.sh first!"
    exit 1
fi

# Check if editors are built
if [ ! -f "$SCRIPT_DIR/ee" ] || [ ! -f "$SCRIPT_DIR/virus" ]; then
    echo "ERROR: Editors not found. Run ./setup-test.sh first!"
    exit 1
fi

# Create directory structure if needed
if [ ! -d "$TEST_DIR" ]; then
    echo "Creating test environment..."
    mkdir -p "$TEST_DIR"/{dgldir,userdata,inprogress,ttyrec,rcfiles,var/mail,bin}
else
    echo "Using existing test environment..."
fi

# Copy binaries
echo "Updating binaries..."
cp "$SCRIPT_DIR/dgamelaunch" "$TEST_DIR/"
cp "$SCRIPT_DIR/ee" "$TEST_DIR/bin/"
cp "$SCRIPT_DIR/virus" "$TEST_DIR/bin/"

# Detect build type
if strings "$TEST_DIR/dgamelaunch" | grep -q "USE_SQLITE3"; then
    BUILD_TYPE="sqlite"
    echo "Detected SQLite build"
    
    # Initialize database if needed
    if [ ! -f "$TEST_DIR/dgamelaunch.db" ]; then
        echo "Initializing SQLite database..."
        if ! command -v sqlite3 >/dev/null 2>&1; then
            echo "ERROR: sqlite3 command not found. Install sqlite3 package!"
            exit 1
        fi
        
        sqlite3 "$TEST_DIR/dgamelaunch.db" << 'EOF'
CREATE TABLE IF NOT EXISTS dglusers (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL COLLATE NOCASE,
    email TEXT,
    env TEXT,
    password TEXT,
    flags INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_username ON dglusers(username);
EOF
    else
        echo "Using existing SQLite database"
        # Show existing users
        echo "Registered users:"
        sqlite3 "$TEST_DIR/dgamelaunch.db" "SELECT username, email FROM dglusers;" 2>/dev/null || echo "  (none)"
    fi
else
    BUILD_TYPE="flatfile"
    echo "Detected flat file build"
    touch "$TEST_DIR/dgl-login"
    touch "$TEST_DIR/dgl-lock"
    
    if [ -s "$TEST_DIR/dgl-login" ]; then
        echo "Registered users:"
        cut -d: -f1 "$TEST_DIR/dgl-login" | sed 's/^/  /'
    fi
fi

# Create configuration file
echo "Creating configuration..."
cat > "$TEST_DIR/dgamelaunch.conf" << EOF
# DGamelaunch test configuration
chroot_path = "/"
dglroot = "$TEST_DIR/dgldir/"

# Drop privileges to non-root user
shed_uid = $SHED_UID
shed_gid = $SHED_GID

# Basic settings
maxusers = 64000
allow_new_nicks = yes
maxnicklen = 16
locale = "en_US.UTF-8"
default_term = "xterm"
utf8esc = no
flowcontrol = no

# File paths
banner = "$TEST_DIR/dgl-banner"
EOF

# Add database-specific config
if [ "$BUILD_TYPE" = "flatfile" ]; then
    cat >> "$TEST_DIR/dgamelaunch.conf" << EOF
passwd = "$TEST_DIR/dgl-login"
lockfile = "$TEST_DIR/dgl-lock"
EOF
fi

# Continue with common config
cat >> "$TEST_DIR/dgamelaunch.conf" << EOF

# Commands after registration/login
commands[register] = mkdir "$TEST_DIR/userdata/%N",
                     mkdir "$TEST_DIR/userdata/%N/%n",
                     mkdir "$TEST_DIR/userdata/%N/%n/ttyrec"

commands[login] = mkdir "$TEST_DIR/userdata/%N",
                  mkdir "$TEST_DIR/userdata/%N/%n",
                  mkdir "$TEST_DIR/userdata/%N/%n/ttyrec",
                  setenv "HOME" "$TEST_DIR/dgldir"

filemode = "0666"

# NetHack 3.6.7 definition
DEFINE {
  game_id = "NH36"
  game_name = "NetHack 3.6.7"
  game_path = "$NETHACK_PATH/nethack"
  short_name = "NH36"
  game_args = "./nethack", "-u", "%n"
  inprogressdir = "$TEST_DIR/inprogress/"
  ttyrecdir = "$TEST_DIR/userdata/%N/%n/ttyrec/"
  spooldir = "$TEST_DIR/var/mail/"
  rc_fmt = "$TEST_DIR/userdata/%N/%n/nethackrc"
  encoding = "unicode"
  
  # Commands before game starts
  commands = chdir "$NETHACK_PATH",
             mkdir "$TEST_DIR/userdata/%N/%n/nethack",
             mkdir "$TEST_DIR/userdata/%N/%n/nethack/save",
             ifnxcp "$TEST_DIR/default.nethackrc" "$TEST_DIR/userdata/%N/%n/nethackrc",
             setenv "NETHACKOPTIONS" "@$TEST_DIR/userdata/%N/%n/nethackrc",
             setenv "MAIL" "$TEST_DIR/var/mail/%n",
             setenv "SIMPLEMAIL" "1"
}

# Menus
menu["mainmenu_anon"] {
  bannerfile = "$TEST_DIR/dgl-banner-anon"
  cursor = (5,0)
  commands["l"] = ask_login
  commands["r"] = ask_register
  commands["w"] = watch_menu
  commands["q"] = quit
}

menu["mainmenu_user"] {
  bannerfile = "$TEST_DIR/dgl-banner-user"
  cursor = (7,0)
  commands["p"] = play_game "NH36"
  commands["w"] = watch_menu
  commands["c"] = chpasswd
  commands["m"] = chmail
  commands["e"] = exec "$TEST_DIR/bin/ee" "$TEST_DIR/userdata/%N/%n/nethackrc"
  commands["v"] = exec "$TEST_DIR/bin/virus" "$TEST_DIR/userdata/%N/%n/nethackrc"
  commands["q"] = quit
}

menu["watchmenu"] {
  bannerfile = "$TEST_DIR/dgl-banner-watch"
  commands["q"] = return
}
EOF

# Create banner files
cat > "$TEST_DIR/dgl-banner-anon" << 'EOF'
=== DGamelaunch Test Server ===

l) Login
r) Register new account
w) Watch games
q) Quit

EOF

cat > "$TEST_DIR/dgl-banner-user" << 'EOF'
=== DGamelaunch Test Server ===
Logged in as: $USERNAME

p) Play NetHack 3.6.7
w) Watch games
c) Change password
m) Change email
e) Edit RC file (ee)
v) Edit RC file (virus)
q) Quit

EOF

cat > "$TEST_DIR/dgl-banner-watch" << 'EOF'
=== Watch Menu ===

q) Return to main menu

EOF

# Default banner
cp "$TEST_DIR/dgl-banner-anon" "$TEST_DIR/dgl-banner"

# Create default RC file
echo "OPTIONS=color,showexp,time,!autopickup" > "$TEST_DIR/default.nethackrc"

# Set permissions and ownership
chmod -R 755 "$TEST_DIR"
if [ "$(id -u)" -eq 0 ]; then
    # If running as root, chown directories to the target user
    chown -R $SHED_UID:$SHED_GID "$TEST_DIR"
fi

# Check NetHack installation
if [ ! -f "$NETHACK_PATH/nethack" ]; then
    echo ""
    echo "WARNING: NetHack not found at $NETHACK_PATH"
    echo "Set NETHACK_PATH environment variable to point to NetHack installation"
fi

# Check NetHack permissions (if it exists)
if [ -f "$NETHACK_PATH/var/perm" ]; then
    if [ ! -w "$NETHACK_PATH/var/perm" ]; then
        echo ""
        echo "WARNING: NetHack var files may not be writable. You may need to run:"
        echo "  sudo chmod 666 $NETHACK_PATH/var/{perm,record,logfile,xlogfile}"
        echo "  sudo chmod 777 $NETHACK_PATH/var $NETHACK_PATH/var/save"
        echo "  sudo chmod 644 $NETHACK_PATH/sysconf"
    fi
fi

echo ""
echo "=== Launching dgamelaunch ==="
echo "Build type: $BUILD_TYPE"
echo ""

# Launch dgamelaunch
cd "$TEST_DIR"

# Enable debug mode if requested
if [ "$1" = "--debug" ]; then
    echo "Running in debug mode..."
    exec ./dgamelaunch -d
else
    exec ./dgamelaunch
fi
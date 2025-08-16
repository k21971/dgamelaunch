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
ZORK_PATH="/usr/games/lib/zork1"
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
echo "Zork path: $ZORK_PATH"
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

# Check for Zork support - prefer newer z3 file
ZORK_AVAILABLE=0
ZORK_SOURCE=""
if [ -f "/home/build/zork1/COMPILED/zork1.z3" ]; then
    ZORK_SOURCE="/home/build/zork1/COMPILED/zork1.z3"
    ZORK_AVAILABLE=1
    echo "Zork I support detected (using newer z3 version)"
elif [ -f "$ZORK_PATH/Zork1.dat" ]; then
    ZORK_SOURCE="$ZORK_PATH/Zork1.dat"
    ZORK_AVAILABLE=1
    echo "Zork I support detected (using original dat version)"
fi

if [ $ZORK_AVAILABLE -eq 1 ] && ! (command -v dfrotz >/dev/null 2>&1 || command -v frotz >/dev/null 2>&1); then
    ZORK_AVAILABLE=0
    echo "NOTE: frotz/dfrotz not installed - Zork will not be available"
elif [ $ZORK_AVAILABLE -eq 0 ]; then
    echo "NOTE: No Zork data file found - Zork will not be available"
fi

# Create directory structure if needed
if [ ! -d "$TEST_DIR" ]; then
    echo "Creating test environment..."
    mkdir -p "$TEST_DIR"/{dgldir,userdata,inprogress,ttyrec,rcfiles,var/mail,bin}
    mkdir -p "$TEST_DIR"/inprogress-{nh36,zork1}
    mkdir -p "$TEST_DIR"/ttyrec-zork
else
    echo "Using existing test environment..."
fi

# Copy binaries
echo "Updating binaries..."
cp "$SCRIPT_DIR/dgamelaunch" "$TEST_DIR/"
cp "$SCRIPT_DIR/ee" "$TEST_DIR/bin/"
cp "$SCRIPT_DIR/virus" "$TEST_DIR/bin/"

# Compile and copy Zork wrapper if available
if [ $ZORK_AVAILABLE -eq 1 ] && [ -f "$SCRIPT_DIR/zork1-wrapper.c" ]; then
    echo "Compiling Zork wrapper..."
    # Create a temporary version with test paths
    sed -e "s|/zork1/Zork1.dat|$ZORK_PATH/Zork1.dat|g" \
        -e "s|/dgldir/userdata|$TEST_DIR/userdata|g" \
        -e "s|/bin/frotz|$TEST_DIR/bin/frotz|g" \
        "$SCRIPT_DIR/zork1-wrapper.c" > "$TEST_DIR/zork1-wrapper-test.c"
    gcc -O2 -Wall -o "$TEST_DIR/bin/zork1-wrapper" "$TEST_DIR/zork1-wrapper-test.c"
    if [ $? -eq 0 ]; then
        chmod +x "$TEST_DIR/bin/zork1-wrapper"
        rm "$TEST_DIR/zork1-wrapper-test.c"
    else
        echo "Warning: Failed to compile Zork wrapper"
        ZORK_AVAILABLE=0
    fi

    # Copy frotz to test environment
    if command -v frotz >/dev/null 2>&1; then
        cp "$(which frotz)" "$TEST_DIR/bin/"
    else
        echo "Warning: frotz not found, Zork may not work"
        ZORK_AVAILABLE=0
    fi

    # Copy Zork data file to test environment (simulate chroot structure)
    if [ -n "$ZORK_SOURCE" ]; then
        mkdir -p "$TEST_DIR/$ZORK_PATH"
        cp "$ZORK_SOURCE" "$TEST_DIR/$ZORK_PATH/Zork1.dat"
    fi
fi

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

        # Initialize separate IP database
        echo "Initializing IP database..."
        sqlite3 "$TEST_DIR/dgamelaunch_ip.db" << 'EOF'
CREATE TABLE IF NOT EXISTS user_ip_history (
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    connection_count INTEGER DEFAULT 1,
    PRIMARY KEY (username, ip_address)
);
CREATE INDEX IF NOT EXISTS idx_ip_history_last_seen ON user_ip_history(last_seen);
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

# Debug log (if compiled with --enable-debugfile)
debuglogfile = "$TEST_DIR/dgldebug.log"

# Separate IP database for multi-server deployments
ip_database = "$TEST_DIR/dgamelaunch_ip.db"
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
                     mkdir "$TEST_DIR/userdata/%N/%n/ttyrec",
                     mkdir "$TEST_DIR/userdata/%N/%n/ttyrec-zork",
                     mkdir "$TEST_DIR/userdata/%N/%n/zork1"

commands[login] = mkdir "$TEST_DIR/userdata/%N",
                  mkdir "$TEST_DIR/userdata/%N/%n",
                  mkdir "$TEST_DIR/userdata/%N/%n/ttyrec",
                  mkdir "$TEST_DIR/userdata/%N/%n/ttyrec-zork",
                  mkdir "$TEST_DIR/userdata/%N/%n/zork1",
                  setenv "HOME" "$TEST_DIR/dgldir"

filemode = "0666"

# NetHack 3.6.7 definition
DEFINE {
  game_id = "NH36"
  game_name = "NetHack 3.6.7"
  game_path = "$NETHACK_PATH/nethack"
  short_name = "NH36"
  game_args = "./nethack", "-u", "%n"
  inprogressdir = "$TEST_DIR/inprogress-nh36/"
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
EOF

# Add Zork definition only if available
if [ $ZORK_AVAILABLE -eq 1 ]; then
cat >> "$TEST_DIR/dgamelaunch.conf" << EOF

# Zork I definition
DEFINE {
  game_id = "ZORK1"
  game_name = "Zork I: The Great Underground Empire"
  game_path = "$TEST_DIR/bin/zork1-wrapper"
  short_name = "Zork1"
  game_args = "$TEST_DIR/bin/zork1-wrapper"
  inprogressdir = "$TEST_DIR/inprogress-zork1/"
  ttyrecdir = "$TEST_DIR/userdata/%N/%n/zork1/ttyrec/"
  max_idle_time = 3600
  encoding = "ascii"

  # Commands before game starts
  commands = mkdir "$TEST_DIR/userdata/%N/%n/zork1",
             mkdir "$TEST_DIR/userdata/%N/%n/zork1/ttyrec",
             setenv "DGL_USER" "%n",
             setenv "HOME" "$TEST_DIR/userdata/%N/%n/zork1"
}
EOF
fi

# Continue with menus
cat >> "$TEST_DIR/dgamelaunch.conf" << EOF

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
EOF

# Add Zork menu option if available
if [ $ZORK_AVAILABLE -eq 1 ]; then
cat >> "$TEST_DIR/dgamelaunch.conf" << EOF
  commands["z"] = play_game "ZORK1"
EOF
fi

# Continue with rest of menu
cat >> "$TEST_DIR/dgamelaunch.conf" << EOF
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

# Create user banner based on available games
if [ $ZORK_AVAILABLE -eq 1 ]; then
cat > "$TEST_DIR/dgl-banner-user" << 'EOF'
=== DGamelaunch Test Server ===
Logged in as: $USERNAME

p) Play NetHack 3.6.7
z) Play Zork I
w) Watch games
c) Change password
m) Change email
e) Edit RC file (ee)
v) Edit RC file (virus)
q) Quit

EOF
else
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
fi

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
echo "=== Test Environment Ready ==="
echo "Build type: $BUILD_TYPE"
if [ "$BUILD_TYPE" = "sqlite" ]; then
    echo "IP logging: Separate database (dgamelaunch_ip.db)"
    echo "  - IP history preserved across server syncs"
    echo "  - Each server maintains its own IP logs"
fi
echo "Games available:"
echo "  - NetHack 3.6.7"
if [ $ZORK_AVAILABLE -eq 1 ]; then
    echo "  - Zork I"
fi
echo ""
echo "=== Launching dgamelaunch ==="
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

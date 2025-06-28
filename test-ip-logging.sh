#!/bin/bash
# Test script to verify IP logging functionality

set -e

TEST_DIR="${DGAMELAUNCH_TEST_DIR:-/tmp/dgl-test}"
DB_FILE="$TEST_DIR/dgamelaunch.db"

echo "=== IP Logging Test Script ==="
echo "Database: $DB_FILE"
echo ""

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "ERROR: Database not found. Run test-dgamelaunch.sh first."
    exit 1
fi

# Function to run SQL query
run_sql() {
    sqlite3 "$DB_FILE" "$1"
}

# Check current schema
echo "1. Checking current database schema..."
echo "   Tables:"
run_sql ".tables" | sed 's/^/   /'

echo ""
echo "2. Checking dglusers table schema..."
run_sql ".schema dglusers" | sed 's/^/   /'

echo ""
echo "3. Checking for IP logging columns..."
if run_sql "PRAGMA table_info(dglusers);" | grep -q "last_ip"; then
    echo "   ✓ last_ip column exists"
else
    echo "   ✗ last_ip column missing - applying schema update..."
    
    # Apply schema changes
    run_sql "ALTER TABLE dglusers ADD COLUMN last_ip TEXT DEFAULT NULL;"
    run_sql "ALTER TABLE dglusers ADD COLUMN last_login_time INTEGER DEFAULT NULL;"
    echo "   ✓ Schema updated"
fi

echo ""
echo "4. Creating IP history table (if not exists)..."
run_sql "CREATE TABLE IF NOT EXISTS user_ip_history (
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    connection_count INTEGER DEFAULT 1,
    PRIMARY KEY (username, ip_address)
);"
run_sql "CREATE INDEX IF NOT EXISTS idx_ip_history_last_seen ON user_ip_history(last_seen);"
echo "   ✓ IP history table ready"

echo ""
echo "5. Current user data with IP info:"
run_sql "SELECT username, email, last_ip, 
         CASE WHEN last_login_time IS NULL THEN 'Never' 
              ELSE datetime(last_login_time, 'unixepoch') 
         END as last_login 
         FROM dglusers;" | column -t -s "|" | sed 's/^/   /'

echo ""
echo "6. IP address history:"
if [ $(run_sql "SELECT COUNT(*) FROM user_ip_history;") -eq 0 ]; then
    echo "   (No IP history recorded yet)"
else
    run_sql "SELECT username, ip_address, 
             datetime(first_seen, 'unixepoch') as first_seen,
             datetime(last_seen, 'unixepoch') as last_seen,
             connection_count
             FROM user_ip_history 
             ORDER BY last_seen DESC;" | column -t -s "|" | sed 's/^/   /'
fi

echo ""
echo "7. Testing IP extraction..."
echo "   Current environment:"
echo "   SSH_CLIENT: ${SSH_CLIENT:-<not set>}"
echo "   SSH_CONNECTION: ${SSH_CONNECTION:-<not set>}"

# Compile and run IP test
if [ -f "get_client_ip.c" ]; then
    gcc -DTEST_GET_CLIENT_IP -o test-get-client-ip get_client_ip.c 2>/dev/null
    if [ -f "test-get-client-ip" ]; then
        echo "   Detected IP: $(./test-get-client-ip | cut -d: -f2 | tr -d ' ')"
        rm -f test-get-client-ip
    fi
fi

echo ""
echo "=== Schema Ready for IP Logging ==="
echo ""
echo "To test IP logging:"
echo "1. Set SSH_CLIENT environment variable:"
echo "   export SSH_CLIENT=\"192.168.1.100 54321 22\""
echo ""
echo "2. Run dgamelaunch test:"
echo "   ./test-dgamelaunch.sh"
echo ""
echo "3. Login and check the database again"
echo ""
echo "Note: IP logging requires code changes to dgamelaunch.c"
echo "See ip_logging_minimal.c for implementation details"
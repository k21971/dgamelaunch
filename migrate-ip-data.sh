#!/bin/bash
# migrate-ip-data.sh - Migrate IP logging data to separate database
#
# This script extracts IP history from the main dgamelaunch database
# and creates a separate IP database for multi-server deployments

set -e

# Configuration
MAIN_DB="${1:-/dgldir/dgamelaunch.db}"
IP_DB="${2:-${MAIN_DB%.db}_ip.db}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== DGamelaunch IP Data Migration ==="
echo "Main database: $MAIN_DB"
echo "IP database:   $IP_DB"
echo ""

# Check if main database exists
if [ ! -f "$MAIN_DB" ]; then
    echo -e "${RED}Error: Main database not found: $MAIN_DB${NC}"
    exit 1
fi

# Check if sqlite3 is available
if ! command -v sqlite3 >/dev/null 2>&1; then
    echo -e "${RED}Error: sqlite3 command not found. Please install sqlite3.${NC}"
    exit 1
fi

# Check if IP database already exists
if [ -f "$IP_DB" ]; then
    echo -e "${YELLOW}Warning: IP database already exists: $IP_DB${NC}"
    read -p "Do you want to merge data into existing database? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting migration."
        exit 1
    fi
fi

# Check if main database has IP data
echo "Checking for existing IP data..."
HAS_IP_HISTORY=$(sqlite3 "$MAIN_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='user_ip_history';" 2>/dev/null || echo "0")

if [ "$HAS_IP_HISTORY" = "0" ]; then
    echo -e "${YELLOW}No user_ip_history table found in main database.${NC}"
    echo "Creating empty IP database..."
else
    # Count records to migrate
    RECORD_COUNT=$(sqlite3 "$MAIN_DB" "SELECT COUNT(*) FROM user_ip_history;" 2>/dev/null || echo "0")
    echo "Found $RECORD_COUNT IP history records to migrate."
fi

# Create/initialize IP database
echo "Initializing IP database..."
sqlite3 "$IP_DB" << 'EOF'
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

# Migrate data if it exists
if [ "$HAS_IP_HISTORY" = "1" ] && [ "$RECORD_COUNT" -gt 0 ]; then
    echo "Migrating IP history data..."
    
    # Export from main database and import to IP database
    sqlite3 "$MAIN_DB" << EOF | sqlite3 "$IP_DB"
.mode insert user_ip_history
SELECT username, ip_address, first_seen, last_seen, connection_count
FROM user_ip_history
ORDER BY last_seen;
EOF
    
    # Verify migration
    MIGRATED_COUNT=$(sqlite3 "$IP_DB" "SELECT COUNT(*) FROM user_ip_history;" 2>/dev/null || echo "0")
    
    if [ "$MIGRATED_COUNT" = "$RECORD_COUNT" ]; then
        echo -e "${GREEN}Successfully migrated $MIGRATED_COUNT records.${NC}"
        
        # Ask about cleanup
        echo ""
        echo -e "${YELLOW}Migration complete. The IP data still exists in the main database.${NC}"
        echo "You may want to remove it after verifying the migration worked correctly."
        echo ""
        echo "To remove IP data from main database later, run:"
        echo "  sqlite3 '$MAIN_DB' 'DROP TABLE IF EXISTS user_ip_history;'"
    else
        echo -e "${RED}Error: Expected $RECORD_COUNT records but only migrated $MIGRATED_COUNT${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}IP database initialized successfully.${NC}"
fi

# Show configuration snippet
echo ""
echo "=== Configuration ==="
echo "Add this line to your dgamelaunch.conf:"
echo -e "${GREEN}ip_database = \"$IP_DB\"${NC}"
echo ""
echo "For multi-server deployments, exclude the IP database from rsync:"
echo -e "${GREEN}rsync ... --exclude='$(basename "$IP_DB")' ...${NC}"

# Set permissions
chmod 644 "$IP_DB" 2>/dev/null || true

echo ""
echo -e "${GREEN}Migration complete!${NC}"
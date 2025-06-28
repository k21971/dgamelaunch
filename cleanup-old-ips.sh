#!/bin/bash
# Cleanup script for dgamelaunch IP history
# Run daily via cron to enforce 90-day retention policy

# Configuration
DB_PATH="/dgldir/dgamelaunch.db"  # Adjust to your actual path
LOG_FILE="/var/log/dgamelaunch-ip-cleanup.log"
RETENTION_DAYS=90

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Start cleanup
log_message "Starting IP retention cleanup (${RETENTION_DAYS}-day policy)"

# Get counts before cleanup
BEFORE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM user_ip_history;" 2>/dev/null || echo "0")
OLD_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM user_ip_history WHERE last_seen < strftime('%s', 'now', '-${RETENTION_DAYS} days');" 2>/dev/null || echo "0")

if [ "$OLD_COUNT" -gt 0 ]; then
    log_message "Found $OLD_COUNT IP records older than $RETENTION_DAYS days"
    
    # Perform cleanup
    sqlite3 "$DB_PATH" <<EOF
-- Delete old IP history
DELETE FROM user_ip_history 
WHERE last_seen < strftime('%s', 'now', '-${RETENTION_DAYS} days');

-- Clear old IPs from user table
UPDATE dglusers 
SET last_ip = NULL 
WHERE last_login_time < strftime('%s', 'now', '-${RETENTION_DAYS} days') 
  AND last_ip IS NOT NULL;

-- Reclaim space
VACUUM;
EOF
    
    # Get count after cleanup
    AFTER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM user_ip_history;" 2>/dev/null || echo "0")
    REMOVED=$((BEFORE_COUNT - AFTER_COUNT))
    
    log_message "Cleanup complete. Removed $REMOVED records. Remaining: $AFTER_COUNT"
else
    log_message "No old records found. Total records: $BEFORE_COUNT"
fi

# Optional: Log current statistics
UNIQUE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT username) FROM user_ip_history;" 2>/dev/null || echo "0")
UNIQUE_IPS=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT ip_address) FROM user_ip_history;" 2>/dev/null || echo "0")

log_message "Current stats: $UNIQUE_USERS users from $UNIQUE_IPS unique IPs"

# Cron example (add to crontab -e):
# Run daily at 3:00 AM
# 0 3 * * * /path/to/cleanup-old-ips.sh
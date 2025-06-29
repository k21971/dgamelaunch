# IP Database Separation for Multi-Server Deployments

This document describes the separate IP database feature added to dgamelaunch
to solve IP logging data loss in multi-server deployments.

## Problem

In multi-server deployments (e.g., hdf-us, hdf-eu, hdf-au), the main
dgamelaunch.db file is synchronized between servers via rsync every 5 minutes.
Since SQLite databases are single binary files, this overwrites all IP logging
data collected on secondary servers, causing data loss.

## Solution

IP logging can now be separated into its own database file that is excluded
from rsync synchronization. Each server maintains its own IP history while
still sharing user accounts.

## Configuration

Add the following to your dgamelaunch.conf:

```
ip_database = "/dgldir/dgamelaunch_ip.db"
```

If not configured, the system defaults to:
- `<main_db>_ip.db` (e.g., `/dgldir/dgamelaunch_ip.db` for `/dgldir/dgamelaunch.db`)
- Falls back to `/dgldir/dgamelaunch_ip.db` if main database path is unavailable

## Migration

For existing installations, use the migration script:

```bash
# Basic migration
./migrate-ip-data.sh

# Or specify paths explicitly
./migrate-ip-data.sh /path/to/dgamelaunch.db /path/to/dgamelaunch_ip.db
```

The migration script will:
1. Create the new IP database with proper schema
2. Copy all existing IP history from the main database
3. Verify the migration succeeded
4. Provide configuration instructions

## Multi-Server Setup

1. **Configure each server** with the same `ip_database` path in dgamelaunch.conf

2. **Exclude from rsync** by adding to your sync script:
   ```bash
   rsync ... --exclude='dgamelaunch_ip.db' ...
   ```

3. **Run migration** on each server to preserve existing IP data

## Database Structure

The separate IP database contains only the `user_ip_history` table:

```sql
CREATE TABLE user_ip_history (
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    connection_count INTEGER DEFAULT 1,
    PRIMARY KEY (username, ip_address)
);
```

The main database no longer stores any IP-related information. All IP logging
is handled exclusively by the separate IP database.

## Cleanup Script Updates

The `cleanup-old-ips.sh` script automatically detects and uses the separate
IP database if it exists. No changes needed to your cron jobs.

## Backward Compatibility

- Old servers without this update continue to work normally
- The configuration option is ignored if not recognized
- IP logging falls back to main database if separate database is unavailable
- Migration can be done gradually across server fleet

## Benefits

1. **No data loss** - Each server maintains complete IP history
2. **Simple deployment** - Just exclude one file from rsync
3. **Easy correlation** - Can still join data via username
4. **Flexible** - Can be enabled per-server or fleet-wide
5. **Non-disruptive** - Existing setups continue working

## Example Deployment Timeline

1. **Day 1**: Update dgamelaunch binary on all servers
2. **Day 2**: Run migration script on each server
3. **Day 3**: Add `ip_database` to config files
4. **Day 4**: Update rsync to exclude IP databases
5. **Day 5**: Verify IP logging working correctly
6. **Day 30**: Optionally remove old IP data from main databases

## Troubleshooting

**IP data not being logged**
- Check file permissions on IP database
- Verify `ip_database` path in config
- Check debug log for database errors

**Migration shows 0 records**
- Ensure main database has `user_ip_history` table
- Check if IP logging was previously enabled

**Cleanup not working**
- Update cleanup script to latest version
- Verify IP database path is correct
- Check cron job output/logs
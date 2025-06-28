# Safe Migration Strategy for Multi-Server IP Logging

## Overview
This document outlines how to safely deploy IP logging across multiple dgamelaunch servers with synchronized databases.

## Key Finding: The upgrade is backward compatible!

Non-upgraded servers will continue to work normally because:
- They use explicit column names in INSERT/UPDATE queries
- SELECT * queries will simply ignore unknown columns
- The new user_ip_history table won't be accessed by old code

## Recommended Migration Steps

### Phase 1: Database Preparation
1. Apply schema changes to the master database:
   ```bash
   sqlite3 /path/to/dgamelaunch.db < add_ip_logging.sql
   ```

2. Let the database sync to all servers as normal

3. Monitor for any issues (there shouldn't be any)

### Phase 2: Gradual Code Deployment
1. Upgrade the least critical server first
2. Monitor for 24-48 hours
3. If no issues, upgrade the next server
4. Finally upgrade the main server

### Phase 3: Verification
After all servers are upgraded:
```sql
-- Check IP logging is working
SELECT username, last_ip, datetime(last_login_time, 'unixepoch') 
FROM dglusers 
WHERE last_ip IS NOT NULL 
ORDER BY last_login_time DESC 
LIMIT 10;
```

## What Happens During Mixed Operation

During the transition period when some servers are upgraded and others aren't:

| Action | Upgraded Server | Non-Upgraded Server |
|--------|----------------|---------------------|
| User registers | IP logged | IP columns get NULL |
| User logs in | IP updated | IP columns unchanged |
| User changes password | IP updated | IP columns unchanged |
| Database syncs | All data preserved | Extra columns ignored |

## Rollback Plan

If issues arise, you can safely rollback:

1. Revert code on upgraded servers
2. The database can stay as-is (extra columns don't hurt)
3. Or remove columns if desired:
   ```sql
   -- Create backup first!
   cp dgamelaunch.db dgamelaunch.db.backup
   
   -- Remove IP logging (SQLite doesn't support DROP COLUMN directly)
   BEGIN TRANSACTION;
   CREATE TABLE dglusers_new AS 
   SELECT id, username, email, env, password, flags 
   FROM dglusers;
   
   DROP TABLE dglusers;
   ALTER TABLE dglusers_new RENAME TO dglusers;
   
   CREATE INDEX idx_username ON dglusers(username);
   
   DROP TABLE IF EXISTS user_ip_history;
   DROP VIEW IF EXISTS user_latest_ips;
   DROP VIEW IF EXISTS user_all_ips;
   
   COMMIT;
   ```

## Testing in Advance

To test compatibility before production:

1. Copy your production database
2. Apply schema changes to the copy
3. Test with both old and new dgamelaunch versions
4. Verify sync behavior

## Monitoring During Migration

Watch for:
- Any errors in dgamelaunch logs
- Database sync failures
- User login issues

Check logs with:
```bash
tail -f /tmp/dgldebug.log  # If debug logging enabled
journalctl -u dgamelaunch  # If using systemd
```

## Long-term Considerations

Once all servers are upgraded:
- IP data will be consistently logged across all servers
- Consider IP retention policies for privacy compliance
- Monitor database size growth from IP history table
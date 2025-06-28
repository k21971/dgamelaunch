-- SQL script to add IP logging to dgamelaunch SQLite database
-- Run this against existing databases to add IP tracking functionality

-- Add last_ip column to dglusers table
ALTER TABLE dglusers ADD COLUMN last_ip TEXT DEFAULT NULL;
ALTER TABLE dglusers ADD COLUMN last_login_time INTEGER DEFAULT NULL;

-- Create IP history table
CREATE TABLE IF NOT EXISTS user_ip_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    connection_count INTEGER DEFAULT 1,
    FOREIGN KEY (username) REFERENCES dglusers(username)
);

-- Create indices for performance
CREATE INDEX IF NOT EXISTS idx_ip_history_username ON user_ip_history(username);
CREATE INDEX IF NOT EXISTS idx_ip_history_ip ON user_ip_history(ip_address);
CREATE INDEX IF NOT EXISTS idx_ip_history_last_seen ON user_ip_history(last_seen);

-- View to see latest IP for each user
CREATE VIEW IF NOT EXISTS user_latest_ips AS
SELECT
    u.username,
    u.email,
    u.last_ip,
    datetime(u.last_login_time, 'unixepoch') as last_login,
    (SELECT COUNT(DISTINCT ip_address) FROM user_ip_history WHERE username = u.username) as unique_ips,
    (SELECT SUM(connection_count) FROM user_ip_history WHERE username = u.username) as total_connections
FROM dglusers u
ORDER BY u.last_login_time DESC;

-- View to see all IPs for a specific user (usage: SELECT * FROM user_all_ips WHERE username='someuser')
CREATE VIEW IF NOT EXISTS user_all_ips AS
SELECT
    username,
    ip_address,
    datetime(first_seen, 'unixepoch') as first_seen_date,
    datetime(last_seen, 'unixepoch') as last_seen_date,
    connection_count
FROM user_ip_history
ORDER BY last_seen DESC;
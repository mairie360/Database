-- What the load test exercised: heaviest statements, then table and index usage.
SELECT round(total_exec_time)::bigint AS total_ms, calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       left(regexp_replace(query, '\s+', ' ', 'g'), 110) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'core')
  AND query NOT ILIKE '%pg_stat%'
ORDER BY total_exec_time DESC LIMIT 15;

-- Tables read mostly by sequential scans under load
SELECT relname, seq_scan, seq_tup_read, idx_scan, n_live_tup
FROM pg_stat_user_tables
WHERE seq_scan > 0 AND n_live_tup > 10000
ORDER BY seq_tup_read DESC LIMIT 10;

-- Indexes never used during the run (excluding unique/PK, which also enforce constraints)
SELECT s.relname, s.indexrelname, pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
  AND pg_relation_size(s.indexrelid) > 1024 * 1024
ORDER BY pg_relation_size(s.indexrelid) DESC;

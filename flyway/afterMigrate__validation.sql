-- =============================================================================
-- afterMigrate__validation.sql
-- Flyway Feature: CALLBACK (afterMigrate)
-- Purpose: Runs after every successful Flyway migrate.
--          Logs migration completion metrics to an audit table.
-- =============================================================================

USE destinationdb;

-- -----------------------------------------------------------------------
-- Create migration audit log table if not present
-- (Flyway does not drop this on clean — it persists across runs)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS _flyway_audit_log (
    audit_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    event         VARCHAR(60)  NOT NULL,
    table_name    VARCHAR(128) NULL,
    row_count     BIGINT       NULL,
    recorded_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id)
) ENGINE=InnoDB COMMENT='Flyway post-migration validation snapshots';

-- -----------------------------------------------------------------------
-- Snapshot row counts after each migration run
-- Used to verify DMS data completeness against Flyway-managed baseline
-- -----------------------------------------------------------------------
INSERT INTO _flyway_audit_log (event, table_name, row_count)
SELECT 'afterMigrate_snapshot', table_name, table_rows
FROM information_schema.TABLES
WHERE table_schema = 'destinationdb'
  AND table_type   = 'BASE TABLE'
  AND table_name   NOT LIKE '_flyway%'
  AND table_name   NOT LIKE 'flyway%';

-- Confirm views are present
INSERT INTO _flyway_audit_log (event, table_name, row_count)
SELECT 'afterMigrate_view_check', table_name, 1
FROM information_schema.VIEWS
WHERE table_schema = 'destinationdb';

SELECT
    'afterMigrate complete' AS flyway_log,
    NOW()                   AS completed_at;

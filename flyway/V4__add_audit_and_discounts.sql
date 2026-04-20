-- =============================================================================
-- V4__add_audit_and_discounts.sql
-- Flyway Feature: Schema Evolution (additive column + new table)
-- Purpose: Post-migration schema enhancements - these columns didn't exist
--          on source (Cloud SQL) and are AWS/RDS-side additions.
--          Run AFTER DMS CDC is quiesced and traffic cut over to RDS.
-- =============================================================================

USE destinationdb;

-- -----------------------------------------------------------------------
-- Add soft-delete + audit trail to orders
-- (source schema didn't have this; added on RDS side post-cutover)
-- -----------------------------------------------------------------------
ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMP NULL DEFAULT NULL AFTER updated_at,
    ADD COLUMN IF NOT EXISTS created_by  VARCHAR(64) NULL DEFAULT NULL AFTER deleted_at,
    ADD COLUMN IF NOT EXISTS migrated_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Populated by DMS; NULL = native RDS row',
    ADD INDEX IF NOT EXISTS idx_deleted  (deleted_at);

-- -----------------------------------------------------------------------
-- Discount / coupon codes table (new feature, does not exist on source)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discount_codes (
    code_id        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    code           VARCHAR(32)     NOT NULL,
    discount_type  ENUM('percent','fixed') NOT NULL DEFAULT 'percent',
    discount_value DECIMAL(8,2)    NOT NULL,
    min_order_amt  DECIMAL(10,2)   NULL DEFAULT 0.00,
    max_uses       INT UNSIGNED    NULL COMMENT 'NULL = unlimited',
    used_count     INT UNSIGNED    NOT NULL DEFAULT 0,
    valid_from     DATE            NOT NULL,
    valid_until    DATE            NULL,
    is_active      TINYINT(1)      NOT NULL DEFAULT 1,
    created_at     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (code_id),
    UNIQUE KEY uq_code (code),
    KEY idx_valid (valid_from, valid_until, is_active)
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Promotional discount codes - RDS-side feature post-cutover';

-- Seed initial discount codes
INSERT INTO discount_codes (code, discount_type, discount_value, min_order_amt, max_uses, valid_from, valid_until) VALUES
('WELCOME10',  'percent', 10.00, 0.00,    1000, '2024-01-01', '2024-12-31'),
('SAVE50NOW',  'fixed',   50.00, 500.00,   500, '2024-03-01', '2024-06-30'),
('GOLDMEMBER', 'percent', 15.00, 100.00,  NULL, '2024-01-01', NULL),
('APAC2024',   'percent', 12.00, 200.00,   250, '2024-04-01', '2024-09-30')
ON DUPLICATE KEY UPDATE discount_value = VALUES(discount_value);

-- -----------------------------------------------------------------------
-- Mark migrated rows (audit trail for post-migration verification)
-- -----------------------------------------------------------------------
UPDATE orders
SET migrated_at = NOW()
WHERE migrated_at IS NULL;

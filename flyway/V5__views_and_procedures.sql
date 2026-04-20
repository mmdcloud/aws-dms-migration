-- =============================================================================
-- V5__views_and_procedures.sql
-- Flyway Feature: DDL for non-table objects (Views, Stored Procedures)
-- Purpose: Application-layer abstractions created on RDS after data verified.
--          These cannot be replicated by DMS and must be deployed by Flyway.
-- =============================================================================

USE destinationdb;

-- -----------------------------------------------------------------------
-- View: v_order_summary
-- Used by reporting API; hides raw JOIN complexity
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.status,
    o.currency,
    o.total_amount,
    o.ordered_at,
    o.migrated_at,
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.email,
    c.tier,
    r.region_name,
    w.warehouse_name,
    COUNT(oi.item_id)   AS line_count,
    SUM(oi.qty)         AS total_units
FROM orders o
JOIN customers  c  ON c.customer_id  = o.customer_id
LEFT JOIN regions    r  ON r.region_id   = c.region_id
LEFT JOIN warehouses w  ON w.warehouse_id = o.warehouse_id
LEFT JOIN order_items oi ON oi.order_id  = o.order_id
WHERE o.deleted_at IS NULL
GROUP BY
    o.order_id, o.status, o.currency, o.total_amount, o.ordered_at, o.migrated_at,
    c.customer_id, customer_name, c.email, c.tier, r.region_name, w.warehouse_name;

-- -----------------------------------------------------------------------
-- View: v_inventory_health
-- Shows stock-out risk per product per warehouse
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_inventory_health AS
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    w.warehouse_id,
    w.warehouse_name,
    i.qty_on_hand,
    i.qty_reserved,
    (i.qty_on_hand - i.qty_reserved) AS qty_available,
    i.reorder_point,
    CASE
        WHEN (i.qty_on_hand - i.qty_reserved) <= 0         THEN 'OUT_OF_STOCK'
        WHEN (i.qty_on_hand - i.qty_reserved) <= i.reorder_point THEN 'LOW_STOCK'
        ELSE 'OK'
    END AS stock_status
FROM inventory i
JOIN products   p ON p.product_id   = i.product_id
JOIN warehouses w ON w.warehouse_id = i.warehouse_id
WHERE p.is_active = 1;

-- -----------------------------------------------------------------------
-- Stored Procedure: sp_get_customer_lifetime_value
-- Returns LTV metrics for a given customer
-- -----------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_get_customer_lifetime_value;

DELIMITER $$

CREATE PROCEDURE sp_get_customer_lifetime_value(IN p_customer_id INT UNSIGNED)
BEGIN
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        c.tier,
        COUNT(DISTINCT o.order_id)              AS total_orders,
        SUM(o.total_amount)                     AS lifetime_value,
        AVG(o.total_amount)                     AS avg_order_value,
        MIN(o.ordered_at)                       AS first_order_date,
        MAX(o.ordered_at)                       AS latest_order_date,
        DATEDIFF(MAX(o.ordered_at), MIN(o.ordered_at)) AS days_as_customer
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id
                       AND o.status NOT IN ('cancelled', 'refunded')
                       AND o.deleted_at IS NULL
    WHERE c.customer_id = p_customer_id
    GROUP BY c.customer_id, customer_name, c.tier;
END$$

DELIMITER ;

-- -----------------------------------------------------------------------
-- Stored Procedure: sp_reserve_inventory
-- Atomically reserves stock; returns 0=success, 1=insufficient stock
-- -----------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_reserve_inventory;

DELIMITER $$

CREATE PROCEDURE sp_reserve_inventory(
    IN  p_product_id   INT UNSIGNED,
    IN  p_warehouse_id SMALLINT UNSIGNED,
    IN  p_qty          SMALLINT,
    OUT p_result       TINYINT
)
BEGIN
    DECLARE v_available INT DEFAULT 0;

    START TRANSACTION;

    SELECT (qty_on_hand - qty_reserved)
    INTO   v_available
    FROM   inventory
    WHERE  product_id   = p_product_id
      AND  warehouse_id = p_warehouse_id
    FOR UPDATE;

    IF v_available >= p_qty THEN
        UPDATE inventory
        SET    qty_reserved = qty_reserved + p_qty
        WHERE  product_id   = p_product_id
          AND  warehouse_id = p_warehouse_id;
        SET p_result = 0; -- success
        COMMIT;
    ELSE
        SET p_result = 1; -- insufficient stock
        ROLLBACK;
    END IF;
END$$

DELIMITER ;

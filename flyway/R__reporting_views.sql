-- =============================================================================
-- R__reporting_views.sql
-- Flyway Feature: REPEATABLE Migration (R__ prefix)
-- Purpose: Flyway re-runs this file whenever its checksum changes.
--          Use for views/functions you iterate on without version bumping.
--          File must be fully idempotent (CREATE OR REPLACE).
-- =============================================================================

USE destinationdb;

-- -----------------------------------------------------------------------
-- Reporting view: daily revenue (re-runnable, evolves over time)
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_daily_revenue AS
SELECT
    DATE(o.ordered_at)          AS order_date,
    o.currency,
    COUNT(DISTINCT o.order_id)  AS order_count,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(o.subtotal)             AS gross_revenue,
    SUM(o.tax_amount)           AS tax_collected,
    SUM(o.shipping_amount)      AS shipping_revenue,
    SUM(o.total_amount)         AS net_revenue,
    AVG(o.total_amount)         AS avg_order_value
FROM orders o
WHERE o.status NOT IN ('cancelled', 'refunded')
  AND o.deleted_at IS NULL
GROUP BY DATE(o.ordered_at), o.currency;

-- -----------------------------------------------------------------------
-- Reporting view: top products by revenue
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_top_products AS
SELECT
    p.product_id,
    p.sku,
    p.product_name,
    cat.category_name,
    SUM(oi.qty)         AS units_sold,
    SUM(oi.line_total)  AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS order_appearances,
    AVG(oi.unit_price)  AS avg_selling_price
FROM order_items oi
JOIN products   p   ON p.product_id   = oi.product_id
LEFT JOIN categories cat ON cat.category_id = p.category_id
GROUP BY p.product_id, p.sku, p.product_name, cat.category_name;

-- -----------------------------------------------------------------------
-- Reporting view: regional sales heatmap
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_regional_sales AS
SELECT
    r.region_name,
    r.country,
    COUNT(DISTINCT o.customer_id) AS active_customers,
    COUNT(DISTINCT o.order_id)    AS total_orders,
    SUM(o.total_amount)           AS total_revenue,
    AVG(o.total_amount)           AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN regions   r ON r.region_id   = c.region_id
WHERE o.status NOT IN ('cancelled', 'refunded')
  AND o.deleted_at IS NULL
GROUP BY r.region_name, r.country;

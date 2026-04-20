-- =============================================================================
-- V3__post_migration_indexes.sql
-- Flyway Feature: Versioned Migration (additive, safe to run after DMS full-load)
-- Purpose: Add indexes dropped pre-migration to speed up DMS full-load,
--          now re-applied post-load for query performance on RDS.
--
-- DMS Best Practice: Drop secondary indexes on target before full-load,
-- re-add after. This migration handles the "re-add" step automatically.
-- =============================================================================

USE destinationdb;

-- Composite covering index for order status dashboard
-- Covers: WHERE status = ? ORDER BY ordered_at DESC
ALTER TABLE orders
    ADD INDEX IF NOT EXISTS idx_status_date (status, ordered_at DESC);

-- Covering index for customer order history queries
-- Covers: WHERE customer_id = ? ORDER BY ordered_at DESC LIMIT n
ALTER TABLE orders
    ADD INDEX IF NOT EXISTS idx_customer_date (customer_id, ordered_at DESC, total_amount);

-- Inventory availability query (products below reorder threshold)
-- Covers: WHERE qty_on_hand <= reorder_point AND warehouse_id = ?
ALTER TABLE inventory
    ADD INDEX IF NOT EXISTS idx_reorder_check (warehouse_id, qty_on_hand, reorder_point);

-- Product catalogue browsing: active products by category, price sorted
ALTER TABLE products
    ADD INDEX IF NOT EXISTS idx_cat_price_active (category_id, is_active, unit_price);

-- Customer tier + region analytics
ALTER TABLE customers
    ADD INDEX IF NOT EXISTS idx_tier_region (tier, region_id, is_active);

-- Order items product sales reporting
ALTER TABLE order_items
    ADD INDEX IF NOT EXISTS idx_product_sales (product_id, created_at);

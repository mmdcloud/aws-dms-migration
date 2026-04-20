-- =============================================================================
-- V1__baseline_schema.sql
-- Flyway Feature: Versioned Migration (V prefix)
-- Purpose: Baseline schema creation - run ONCE, never edited after apply
-- Source: Cloud SQL MySQL 8.0 (madmax DB, us-central1)
-- Target: RDS MySQL 8.0 (destinationdb, us-east-1)
-- =============================================================================

-- DMS migrates data; Flyway owns the schema DDL.
-- This baseline creates the exact schema DMS will find on the source
-- so RDS is ready before DMS full-load begins.

CREATE DATABASE IF NOT EXISTS destinationdb
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE destinationdb;

-- -----------------------------------------------------------------------
-- 1. regions  (lookup, no FK deps)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS regions (
    region_id   TINYINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    region_name VARCHAR(100)      NOT NULL,
    country     VARCHAR(100)      NOT NULL,
    timezone    VARCHAR(50)       NOT NULL DEFAULT 'UTC',
    created_at  TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (region_id),
    UNIQUE KEY uq_region_name (region_name)
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Geographical regions for warehouse and customer assignment';

-- -----------------------------------------------------------------------
-- 2. categories  (self-referencing hierarchy)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
    category_id   SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    parent_id     SMALLINT UNSIGNED NULL,
    category_name VARCHAR(150)      NOT NULL,
    slug          VARCHAR(160)      NOT NULL,
    depth         TINYINT UNSIGNED  NOT NULL DEFAULT 0,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1,
    created_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_slug (slug),
    KEY idx_parent (parent_id),
    CONSTRAINT fk_cat_parent FOREIGN KEY (parent_id)
        REFERENCES categories (category_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Product category tree - supports unlimited depth via parent_id';

-- -----------------------------------------------------------------------
-- 3. customers
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    customer_id   INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    email         VARCHAR(254)      NOT NULL,
    first_name    VARCHAR(80)       NOT NULL,
    last_name     VARCHAR(80)       NOT NULL,
    phone         VARCHAR(20)       NULL,
    region_id     TINYINT UNSIGNED  NULL,
    tier          ENUM('standard','silver','gold','platinum')
                                    NOT NULL DEFAULT 'standard',
    is_active     TINYINT(1)        NOT NULL DEFAULT 1,
    created_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id),
    UNIQUE KEY uq_email (email),
    KEY idx_region (region_id),
    KEY idx_tier   (tier),
    CONSTRAINT fk_cust_region FOREIGN KEY (region_id)
        REFERENCES regions (region_id)
        ON DELETE SET NULL
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='End-customer master table';

-- -----------------------------------------------------------------------
-- 4. products
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
    product_id    INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    category_id   SMALLINT UNSIGNED NULL,
    sku           VARCHAR(64)       NOT NULL,
    product_name  VARCHAR(255)      NOT NULL,
    description   TEXT              NULL,
    unit_price    DECIMAL(10,2)     NOT NULL,
    cost_price    DECIMAL(10,2)     NOT NULL,
    weight_kg     DECIMAL(6,3)      NULL,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1,
    created_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id),
    UNIQUE KEY uq_sku (sku),
    KEY idx_category (category_id),
    FULLTEXT KEY ft_product_name (product_name),
    CONSTRAINT fk_prod_category FOREIGN KEY (category_id)
        REFERENCES categories (category_id)
        ON DELETE SET NULL
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Product catalogue';

-- -----------------------------------------------------------------------
-- 5. warehouses
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS warehouses (
    warehouse_id   SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    region_id      TINYINT UNSIGNED  NULL,
    warehouse_name VARCHAR(120)      NOT NULL,
    address        VARCHAR(300)      NULL,
    capacity_sqft  INT UNSIGNED      NULL,
    is_active      TINYINT(1)        NOT NULL DEFAULT 1,
    created_at     TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (warehouse_id),
    KEY idx_region (region_id),
    CONSTRAINT fk_wh_region FOREIGN KEY (region_id)
        REFERENCES regions (region_id)
        ON DELETE SET NULL
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Physical warehouse locations';

-- -----------------------------------------------------------------------
-- 6. inventory
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory (
    inventory_id  BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    product_id    INT UNSIGNED      NOT NULL,
    warehouse_id  SMALLINT UNSIGNED NOT NULL,
    qty_on_hand   INT               NOT NULL DEFAULT 0,
    qty_reserved  INT               NOT NULL DEFAULT 0,
    reorder_point INT               NOT NULL DEFAULT 10,
    updated_at    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (inventory_id),
    UNIQUE KEY uq_product_warehouse (product_id, warehouse_id),
    KEY idx_warehouse (warehouse_id),
    CONSTRAINT fk_inv_product   FOREIGN KEY (product_id)   REFERENCES products   (product_id) ON DELETE CASCADE,
    CONSTRAINT fk_inv_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (warehouse_id) ON DELETE CASCADE
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Per-warehouse stock levels with reservation tracking';

-- -----------------------------------------------------------------------
-- 7. orders
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    order_id        BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    customer_id     INT UNSIGNED      NOT NULL,
    warehouse_id    SMALLINT UNSIGNED NULL,
    status          ENUM('pending','confirmed','processing','shipped','delivered','cancelled','refunded')
                                      NOT NULL DEFAULT 'pending',
    currency        CHAR(3)           NOT NULL DEFAULT 'USD',
    subtotal        DECIMAL(12,2)     NOT NULL,
    tax_amount      DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
    shipping_amount DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
    total_amount    DECIMAL(12,2)     NOT NULL,
    notes           TEXT              NULL,
    ordered_at      TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id),
    KEY idx_customer  (customer_id),
    KEY idx_status    (status),
    KEY idx_ordered   (ordered_at),
    CONSTRAINT fk_ord_customer  FOREIGN KEY (customer_id)  REFERENCES customers  (customer_id),
    CONSTRAINT fk_ord_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (warehouse_id) ON DELETE SET NULL
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Order header - one row per customer order';

-- -----------------------------------------------------------------------
-- 8. order_items
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_items (
    item_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    order_id      BIGINT UNSIGNED NOT NULL,
    product_id    INT UNSIGNED    NOT NULL,
    qty           SMALLINT        NOT NULL DEFAULT 1,
    unit_price    DECIMAL(10,2)   NOT NULL,
    line_total    DECIMAL(12,2)   NOT NULL,
    created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (item_id),
    KEY idx_order   (order_id),
    KEY idx_product (product_id),
    CONSTRAINT fk_item_order   FOREIGN KEY (order_id)   REFERENCES orders   (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_item_product FOREIGN KEY (product_id) REFERENCES products (product_id)
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Order line items - one row per product per order';

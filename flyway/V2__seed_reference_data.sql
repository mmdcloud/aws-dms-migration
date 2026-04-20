-- =============================================================================
-- V2__seed_reference_data.sql
-- Flyway Feature: Versioned Migration with DML (seed data)
-- Purpose: Populate immutable reference/lookup data that DMS will NOT replicate
--          (small lookup tables that are pre-seeded, not in binlog scope)
-- =============================================================================

USE destinationdb;

-- -----------------------------------------------------------------------
-- Regions
-- -----------------------------------------------------------------------
INSERT INTO regions (region_id, region_name, country, timezone) VALUES
(1,  'US East',       'United States', 'America/New_York'),
(2,  'US Central',    'United States', 'America/Chicago'),
(3,  'US West',       'United States', 'America/Los_Angeles'),
(4,  'EU West',       'Germany',       'Europe/Berlin'),
(5,  'APAC South',    'India',         'Asia/Kolkata'),
(6,  'APAC East',     'Singapore',     'Asia/Singapore'),
(7,  'LATAM',         'Brazil',        'America/Sao_Paulo'),
(8,  'CA Central',    'Canada',        'America/Toronto')
ON DUPLICATE KEY UPDATE
    region_name = VALUES(region_name),
    timezone    = VALUES(timezone);

-- -----------------------------------------------------------------------
-- Categories (L0 root → L1 sub → L2 leaf)
-- -----------------------------------------------------------------------
INSERT INTO categories (category_id, parent_id, category_name, slug, depth) VALUES
-- L0
(1,  NULL, 'Electronics',        'electronics',              0),
(2,  NULL, 'Apparel',            'apparel',                  0),
(3,  NULL, 'Home & Garden',      'home-garden',              0),
-- L1
(4,  1,    'Computers',          'electronics/computers',    1),
(5,  1,    'Mobile Devices',     'electronics/mobile',       1),
(6,  2,    'Men\'s',             'apparel/mens',             1),
(7,  2,    'Women\'s',           'apparel/womens',           1),
(8,  3,    'Kitchen',            'home-garden/kitchen',      1),
-- L2
(9,  4,    'Laptops',            'electronics/computers/laptops',   2),
(10, 5,    'Smartphones',        'electronics/mobile/smartphones',  2)
ON DUPLICATE KEY UPDATE
    category_name = VALUES(category_name),
    slug          = VALUES(slug);

-- -----------------------------------------------------------------------
-- Warehouses
-- -----------------------------------------------------------------------
INSERT INTO warehouses (warehouse_id, region_id, warehouse_name, address, capacity_sqft) VALUES
(1, 1, 'Eastern DC',    '100 Fulton St, Newark, NJ 07102',        120000),
(2, 2, 'Central DC',    '500 Distribution Pkwy, Memphis, TN 38118', 95000),
(3, 3, 'Western DC',    '3200 Harbor Blvd, Stockton, CA 95206',   110000),
(4, 4, 'EU Frankfurt',  'Langer Kornweg 34, 65451 Kelsterbach',    80000),
(5, 5, 'India Chennai', 'Plot 42, SIPCOT IT Park, Chennai 600119', 60000)
ON DUPLICATE KEY UPDATE
    warehouse_name = VALUES(warehouse_name),
    address        = VALUES(address);

-- -----------------------------------------------------------------------
-- Products (20 rows across categories)
-- -----------------------------------------------------------------------
INSERT INTO products (product_id, category_id, sku, product_name, unit_price, cost_price, weight_kg) VALUES
(1,  9,  'LAP-DEL-XPS15',    'Dell XPS 15 9530 Laptop',          1799.99, 1320.00, 1.86),
(2,  9,  'LAP-APP-MBP14',    'Apple MacBook Pro 14-inch M3',     1999.00, 1480.00, 1.55),
(3,  9,  'LAP-LEN-X1C',      'Lenovo ThinkPad X1 Carbon Gen11', 1499.00, 1090.00, 1.12),
(4,  10, 'PHN-SAM-S24U',     'Samsung Galaxy S24 Ultra',          1299.99,  890.00, 0.23),
(5,  10, 'PHN-APP-IP15PM',   'Apple iPhone 15 Pro Max',           1199.00,  820.00, 0.22),
(6,  10, 'PHN-GOO-PIX8P',    'Google Pixel 8 Pro',                 999.00,  680.00, 0.21),
(7,  4,  'ACC-USB-HUB7P',    'Anker 7-Port USB-C Hub',              49.99,   22.00, 0.21),
(8,  4,  'ACC-MON-LG27',     'LG 27" 4K IPS Monitor',             449.00,  290.00, 6.50),
(9,  6,  'APR-MEN-CHINO32',  'Slim Fit Chinos 32x32',              59.99,   18.00, 0.45),
(10, 6,  'APR-MEN-POLO-M',   'Pique Polo Shirt Medium',            34.99,   10.00, 0.25),
(11, 7,  'APR-WOM-DRESS-S',  'Wrap Midi Dress Small',              79.99,   25.00, 0.38),
(12, 7,  'APR-WOM-JKT-M',    'Quilted Puffer Jacket Medium',       129.99,  52.00, 0.80),
(13, 8,  'KIT-BLD-NTB5',     'Nutribullet 5-Piece Blender',         89.99,  38.00, 1.60),
(14, 8,  'KIT-NSP-DUO',      'Nespresso Vertuo Next Duo',          149.00,  72.00, 3.10),
(15, 3,  'GRD-SOL-PNL100',   '100W Portable Solar Panel',          219.99,  98.00, 3.50),
(16, 1,  'ELC-SPK-BOSE300',  'Bose SoundLink 300 BT Speaker',      249.00, 135.00, 0.86),
(17, 1,  'ELC-EAR-SONY1000', 'Sony WH-1000XM5 Headphones',         349.00, 195.00, 0.25),
(18, 9,  'LAP-MSF-SRF9',     'Microsoft Surface Pro 9',            1299.00, 920.00, 0.88),
(19, 10, 'PHN-ONE-12P',      'OnePlus 12 Pro 256GB',               799.00,  510.00, 0.22),
(20, 8,  'KIT-IPO-CAST',     'Instant Pot Duo 7-in-1 6qt',        99.95,   44.00, 5.44)
ON DUPLICATE KEY UPDATE
    product_name = VALUES(product_name),
    unit_price   = VALUES(unit_price),
    cost_price   = VALUES(cost_price);

-- -----------------------------------------------------------------------
-- Inventory (product × warehouse combinations)
-- -----------------------------------------------------------------------
INSERT INTO inventory (product_id, warehouse_id, qty_on_hand, qty_reserved, reorder_point) VALUES
-- Laptops mainly East + Central DC
(1,  1, 45,  5, 10), (1, 2, 30,  3, 10),
(2,  1, 60,  8, 15), (2, 3, 25,  2, 10),
(3,  1, 35,  4, 10), (3, 2, 20,  1,  8),
-- Phones spread across 3 DCs
(4,  1, 100, 12, 20), (4, 2, 80,  8, 20), (4, 3, 70, 10, 20),
(5,  1, 150, 18, 25), (5, 2, 90, 10, 20), (5, 3, 110, 14, 20),
(6,  1,  80,  6, 15), (6, 2, 55,  5, 15),
-- Accessories
(7,  1, 200, 20, 30), (7, 2, 180, 15, 30),
(8,  1,  40,  3, 10), (8, 3,  25,  2,  8),
-- Apparel
(9,  2, 300, 40, 50), (9, 3, 250, 30, 50),
(10, 2, 400, 60, 75), (10, 3, 350, 45, 75),
(11, 2, 200, 25, 40), (11, 3, 180, 20, 40),
(12, 1, 150, 18, 30), (12, 2, 130, 15, 30),
-- Kitchen
(13, 1, 120, 10, 20), (13, 2, 100,  8, 20),
(14, 1,  85,  5, 15), (14, 3,  70,  4, 15),
(15, 3,  60,  4, 10),
(16, 1,  90,  6, 15), (16, 2,  75,  5, 15),
(17, 1, 110,  8, 20), (17, 2,  95,  7, 20),
(18, 1,  55,  4, 10), (18, 3,  40,  3,  8),
(19, 2, 130, 10, 20), (19, 3, 100,  8, 20),
(20, 1, 200, 15, 30), (20, 2, 175, 12, 30)
ON DUPLICATE KEY UPDATE
    qty_on_hand   = VALUES(qty_on_hand),
    qty_reserved  = VALUES(qty_reserved),
    reorder_point = VALUES(reorder_point);

-- -----------------------------------------------------------------------
-- Customers (30 sample rows representing source data)
-- -----------------------------------------------------------------------
INSERT INTO customers (customer_id, email, first_name, last_name, phone, region_id, tier) VALUES
(1,  'arjun.sharma@example.com',    'Arjun',    'Sharma',    '+91-9876543210', 5, 'gold'),
(2,  'priya.patel@example.com',     'Priya',    'Patel',     '+91-9988776655', 5, 'silver'),
(3,  'john.doe@example.com',        'John',     'Doe',       '+1-212-555-0101',1, 'platinum'),
(4,  'jane.smith@example.com',      'Jane',     'Smith',     '+1-312-555-0202',2, 'gold'),
(5,  'carlos.mendez@example.com',   'Carlos',   'Mendez',    '+1-213-555-0303',3, 'standard'),
(6,  'anna.mueller@example.com',    'Anna',     'Mueller',   '+49-30-555-0101',4, 'silver'),
(7,  'wei.zhang@example.com',       'Wei',      'Zhang',     '+65-9123-4567',  6, 'gold'),
(8,  'sofia.santos@example.com',    'Sofia',    'Santos',    '+55-11-99999-0001',7,'standard'),
(9,  'liam.tremblay@example.com',   'Liam',     'Tremblay',  '+1-514-555-0404',8, 'silver'),
(10, 'emma.jones@example.com',      'Emma',     'Jones',     '+1-617-555-0505',1, 'gold'),
(11, 'ravi.kumar@example.com',      'Ravi',     'Kumar',     '+91-9123456789', 5, 'standard'),
(12, 'nina.volkova@example.com',    'Nina',     'Volkova',   '+49-89-555-0202',4, 'platinum'),
(13, 'ahmed.ali@example.com',       'Ahmed',    'Ali',       '+65-8234-5678',  6, 'gold'),
(14, 'maria.garcia@example.com',    'Maria',    'Garcia',    '+1-305-555-0606',1, 'silver'),
(15, 'tom.wilson@example.com',      'Tom',      'Wilson',    '+1-415-555-0707',3, 'standard'),
(16, 'yuki.tanaka@example.com',     'Yuki',     'Tanaka',    '+65-9345-6789',  6, 'gold'),
(17, 'omar.hassan@example.com',     'Omar',     'Hassan',    '+55-21-99888-0002',7,'standard'),
(18, 'claire.leblanc@example.com',  'Claire',   'Leblanc',   '+1-604-555-0808',8, 'silver'),
(19, 'raj.gupta@example.com',       'Raj',      'Gupta',     '+91-9234567890', 5, 'gold'),
(20, 'lisa.brown@example.com',      'Lisa',     'Brown',     '+1-718-555-0909',1, 'platinum'),
(21, 'max.bauer@example.com',       'Max',      'Bauer',     '+49-40-555-0303',4, 'silver'),
(22, 'chen.wei@example.com',        'Chen',     'Wei',       '+65-9456-7890',  6, 'standard'),
(23, 'isabela.silva@example.com',   'Isabela',  'Silva',     '+55-31-97777-0003',7,'gold'),
(24, 'noah.martin@example.com',     'Noah',     'Martin',    '+1-416-555-1010',8, 'standard'),
(25, 'aisha.khan@example.com',      'Aisha',    'Khan',      '+91-9345678901', 5, 'silver'),
(26, 'peter.jensen@example.com',    'Peter',    'Jensen',    '+49-211-555-0404',4,'gold'),
(27, 'mei.lim@example.com',         'Mei',      'Lim',       '+65-9567-8901',  6, 'platinum'),
(28, 'lucas.oliveira@example.com',  'Lucas',    'Oliveira',  '+55-41-96666-0004',7,'standard'),
(29, 'sarah.white@example.com',     'Sarah',    'White',     '+1-647-555-1111',8, 'silver'),
(30, 'dev.malhotra@example.com',    'Dev',      'Malhotra',  '+91-9456789012', 5, 'gold')
ON DUPLICATE KEY UPDATE
    tier       = VALUES(tier),
    updated_at = CURRENT_TIMESTAMP;

-- -----------------------------------------------------------------------
-- Orders + Order Items (representative transaction history)
-- -----------------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, warehouse_id, status, currency, subtotal, tax_amount, shipping_amount, total_amount, ordered_at) VALUES
(1,  3,  1, 'delivered',  'USD', 1999.00, 179.91,  0.00, 2178.91, '2024-01-10 09:23:11'),
(2,  1,  5, 'delivered',  'USD', 1299.99, 116.99,  9.99, 1426.97, '2024-01-15 14:10:42'),
(3,  6,  4, 'shipped',    'USD',  449.00,  40.41, 15.00,  504.41, '2024-02-01 08:55:33'),
(4,  10, 1, 'delivered',  'USD', 1499.00, 134.91,  0.00, 1633.91, '2024-02-14 16:30:00'),
(5,  7,  5, 'processing', 'USD',  999.00,  89.91, 12.00, 1100.91, '2024-03-01 11:20:15'),
(6,  20, 1, 'pending',    'USD', 2348.99, 211.41,  0.00, 2560.40, '2024-03-10 07:45:00'),
(7,  12, 4, 'confirmed',  'USD',  349.00,  31.41, 10.00,  390.41, '2024-03-12 13:00:22'),
(8,  4,  2, 'delivered',  'USD',  179.98,  16.19,  5.99,  202.16, '2024-03-20 10:10:10'),
(9,  19, 5, 'delivered',  'USD', 1799.99, 162.00,  0.00, 1961.99, '2024-04-01 09:00:00'),
(10, 27, 5, 'shipped',    'USD', 1199.00, 107.91,  0.00, 1306.91, '2024-04-05 15:30:45')
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO order_items (item_id, order_id, product_id, qty, unit_price, line_total) VALUES
-- Order 1: MacBook
(1,  1, 2, 1, 1999.00, 1999.00),
-- Order 2: Galaxy S24 Ultra + USB Hub
(2,  2, 4, 1, 1299.99, 1299.99),
(3,  2, 7, 1,   49.99,   49.99),
-- Order 3: LG Monitor (EU)
(4,  3, 8, 1,  449.00,  449.00),
-- Order 4: ThinkPad
(5,  4, 3, 1, 1499.00, 1499.00),
-- Order 5: Pixel 8 Pro
(6,  5, 6, 1,  999.00,  999.00),
-- Order 6: MacBook + Galaxy S24 Ultra
(7,  6, 2, 1, 1999.00, 1999.00),
(8,  6, 4, 1, 1299.99, 1299.99),
-- Order 7: Sony Headphones (EU)
(9,  7, 17, 1, 349.00,  349.00),
-- Order 8: 2x Polo Shirt + Chinos
(10, 8, 10, 2,  34.99,   69.98),
(11, 8, 9,  1,  59.99,   59.99),
-- Order 9: Dell XPS
(12, 9, 1,  1, 1799.99, 1799.99),
-- Order 10: iPhone 15 Pro Max (APAC)
(13, 10, 5, 1, 1199.00, 1199.00)
ON DUPLICATE KEY UPDATE qty = VALUES(qty), line_total = VALUES(line_total);

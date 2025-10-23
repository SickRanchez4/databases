-- ===================================================================
-- DATABASE: PRODUCTS & ORDERS (MySQL)
-- ===================================================================

-- Set the engine and character set (InnoDB supports FOREIGN KEYs)
SET default_storage_engine = InnoDB;
SET NAMES utf8mb4;

-- Support tables (Metadata)
CREATE TABLE categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    parent_id INT NULL,
    FOREIGN KEY (parent_id) REFERENCES categories(id)
);

CREATE TABLE brands (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE sizes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(10) NOT NULL UNIQUE,
    sort_order INT
);

CREATE TABLE colors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    hex_code CHAR(7)
);

-- 1. Products table (Parent product)
CREATE TABLE products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE,
    description TEXT,
    category_id INT NOT NULL,
    brand_id INT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    status ENUM('active', 'inactive', 'archived') DEFAULT 'active', 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, 
    FOREIGN KEY (category_id) REFERENCES categories(id),
    FOREIGN KEY (brand_id) REFERENCES brands(id)
);

-- 2. Variants table (Items: Size + Color)
CREATE TABLE product_variants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    color_id INT NOT NULL,
    size_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    is_available BOOLEAN DEFAULT 1, 
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (color_id) REFERENCES colors(id),
    FOREIGN KEY (size_id) REFERENCES sizes(id),
    UNIQUE (product_id, color_id, size_id) 
);

-- 3. Inventory Table (Stock Variation)
CREATE TABLE inventory (
    variant_id BIGINT PRIMARY KEY, -- FK y PK
    stock INT NOT NULL DEFAULT 0,
    reorder_point INT DEFAULT 0,
    last_stock_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, 
    FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE
);

-- 4. Discounts/Coupons Table
CREATE TABLE discounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type ENUM('percentage', 'fixed_amount') NOT NULL, -- CHECK con ENUM
    value DECIMAL(10, 2) NOT NULL,
    expiry_date DATETIME NULL,
    is_active BOOLEAN DEFAULT 1,
    min_order_total DECIMAL(10, 2) DEFAULT 0,
    max_uses INT NULL
);

-- 5. Orders table
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id CHAR(36) NOT NULL,
    shipping_address_json TEXT, 
    tracking_number VARCHAR(100) NULL,
    shipping_carrier VARCHAR(50) NULL,
    discount_code VARCHAR(50) NULL, -- FK a discounts.code
    total DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'paid', 'shipped', 'cancelled', 'completed') DEFAULT 'pending',
    payment_method VARCHAR(50) DEFAULT 'card',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (discount_code) REFERENCES discounts(code)
);

-- 6. Order Items Table
CREATE TABLE order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    variant_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL, 
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (variant_id) REFERENCES product_variants(id)
);

-- 7. Payments table
CREATE TABLE payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'success', 'failed', 'refunded') DEFAULT 'pending',
    transaction_id VARCHAR(255),
    provider_response TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id)
);

-- Indexes
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_status ON products(status);
CREATE INDEX idx_variants_product ON product_variants(product_id);
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_discounts_code_active ON discounts(code, is_active);

-- Trigger for validating stock
DELIMITER $$

CREATE TRIGGER before_order_item_insert
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE available_stock INT;
    
    SELECT stock INTO available_stock
    FROM inventory
    WHERE variant_id = NEW.variant_id;
    
    IF available_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para completar el pedido';
    END IF;
END$$

DELIMITER ;

-- Trigger for updating stock
DELIMITER $$

CREATE TRIGGER after_order_item_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    UPDATE inventory
    SET stock = stock - NEW.quantity
    WHERE variant_id = NEW.variant_id;
END$$

-- Trigger for reverse stock if an order is canceled
CREATE TRIGGER after_order_cancel
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        UPDATE inventory i
        INNER JOIN order_items oi ON i.variant_id = oi.variant_id
        SET i.stock = i.stock + oi.quantity
        WHERE oi.order_id = NEW.id;
    END IF;
END$$

DELIMITER ;

-- Common view
CREATE VIEW product_full_details AS
SELECT 
    p.id AS product_id,
    p.name AS product_name,
    p.base_price,
    c.name AS category,
    b.name AS brand,
    pv.id AS variant_id,
    pv.sku,
    col.name AS color,
    s.name AS size,
    pv.price AS variant_price,
    i.stock,
    p.status
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN brands b ON p.brand_id = b.id
LEFT JOIN product_variants pv ON p.id = pv.product_id
LEFT JOIN colors col ON pv.color_id = col.id
LEFT JOIN sizes s ON pv.size_id = s.id
LEFT JOIN inventory i ON pv.id = i.variant_id;

\connect commerceiq

DROP TABLE IF EXISTS raw.order_reviews  CASCADE;
DROP TABLE IF EXISTS raw.order_payments CASCADE;
DROP TABLE IF EXISTS raw.order_items    CASCADE;
DROP TABLE IF EXISTS raw.orders         CASCADE;
DROP TABLE IF EXISTS raw.products       CASCADE;
DROP TABLE IF EXISTS raw.sellers        CASCADE;
DROP TABLE IF EXISTS raw.customers      CASCADE;
DROP TABLE IF EXISTS raw.product_category_translation CASCADE;

CREATE TABLE raw.customers (
    customer_id               VARCHAR(32)  PRIMARY KEY,
    customer_unique_id        VARCHAR(32)  NOT NULL,
    customer_zip_code_prefix  VARCHAR(5)   NOT NULL,
    customer_city             VARCHAR(100) NOT NULL,
    customer_state            CHAR(2)      NOT NULL
);

CREATE TABLE raw.sellers (
    seller_id               VARCHAR(32)  PRIMARY KEY,
    seller_zip_code_prefix  VARCHAR(5)   NOT NULL,
    seller_city             VARCHAR(100) NOT NULL,
    seller_state            CHAR(2)      NOT NULL
);

CREATE TABLE raw.products (
    product_id                  VARCHAR(32) PRIMARY KEY,
    product_category_name       VARCHAR(100),
    product_name_lenght         INTEGER,
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            INTEGER,
    product_length_cm           INTEGER,
    product_height_cm           INTEGER,
    product_width_cm            INTEGER
);

CREATE TABLE raw.product_category_translation (
    product_category_name          VARCHAR(100) PRIMARY KEY,
    product_category_name_english  VARCHAR(100) NOT NULL
);

CREATE TABLE raw.orders (
    order_id                       VARCHAR(32) PRIMARY KEY,
    customer_id                    VARCHAR(32) NOT NULL REFERENCES raw.customers(customer_id),
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp       TIMESTAMP   NOT NULL,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP   NOT NULL
);

CREATE TABLE raw.order_items (
    order_id             VARCHAR(32)   NOT NULL REFERENCES raw.orders(order_id),
    order_item_id        SMALLINT      NOT NULL,
    product_id           VARCHAR(32)   NOT NULL REFERENCES raw.products(product_id),
    seller_id            VARCHAR(32)   NOT NULL REFERENCES raw.sellers(seller_id),
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2) NOT NULL,
    freight_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE raw.order_payments (
    order_id              VARCHAR(32)   NOT NULL REFERENCES raw.orders(order_id),
    payment_sequential    SMALLINT      NOT NULL,
    payment_type          VARCHAR(20)   NOT NULL,
    payment_installments  SMALLINT      NOT NULL,
    payment_value         NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE raw.order_reviews (
    review_id                VARCHAR(32) NOT NULL,
    order_id                 VARCHAR(32) NOT NULL REFERENCES raw.orders(order_id),
    review_score             SMALLINT    NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP,
    PRIMARY KEY (review_id, order_id)
);

CREATE INDEX idx_orders_customer     ON raw.orders(customer_id);
CREATE INDEX idx_orders_purchase_ts  ON raw.orders(order_purchase_timestamp);
CREATE INDEX idx_items_product       ON raw.order_items(product_id);
CREATE INDEX idx_items_seller        ON raw.order_items(seller_id);
CREATE INDEX idx_reviews_order       ON raw.order_reviews(order_id);
CREATE INDEX idx_customers_unique    ON raw.customers(customer_unique_id);

SELECT table_name FROM information_schema.tables
WHERE table_schema = 'raw' ORDER BY table_name;
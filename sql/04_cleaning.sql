-- =====================================================================
-- CommerceIQ | 04_cleaning.sql
-- Builds the cleaned, analysis-ready layer in schema "analytics".
-- The raw schema is never modified. Safe to re-run.
-- Run: psql -U postgres -d commerceiq -P pager=off -f sql/04_cleaning.sql
--
-- Decisions (all backed by 03_data_quality_checks.sql):
--  * Each fact table has ONE clear grain, so joins cannot duplicate rows.
--  * Revenue = item price only. Freight is a separate column.
--    payment_value is NEVER used as revenue.
--  * VALID ORDER (is_valid_order) = status is not canceled/unavailable
--    AND the order has at least 1 item. Revenue, Total Orders, AOV and
--    customer KPIs use valid orders only.
--  * DELIVERY-ELIGIBLE order (is_delivery_eligible) = status 'delivered'
--    AND delivered_customer_date is not null. Delivery KPIs use only these.
--  * Late = delivered DATE > estimated DATE (estimated dates carry no time).
--  * Reviews: 1 per order (latest answer timestamp).
--  * Payments: payment type = type with the largest value in the order.
--  * Categories: 2 missing English names added manually; NULL -> 'unknown'.
-- =====================================================================

\connect commerceiq

DROP TABLE IF EXISTS analytics.fact_payments    CASCADE;
DROP TABLE IF EXISTS analytics.fact_order_items CASCADE;
DROP TABLE IF EXISTS analytics.fact_reviews     CASCADE;
DROP TABLE IF EXISTS analytics.fact_orders      CASCADE;
DROP TABLE IF EXISTS analytics.dim_customer     CASCADE;
DROP TABLE IF EXISTS analytics.dim_seller       CASCADE;
DROP TABLE IF EXISTS analytics.dim_product      CASCADE;

-- ---------------------------------------------------------------------
-- dim_product : one row per product, with English category
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_product AS
WITH translation AS (
    SELECT product_category_name, product_category_name_english FROM raw.product_category_translation
    UNION ALL
    -- manual additions for categories missing in the source translation file
    SELECT * FROM (VALUES
        ('pc_gamer', 'pc_gamer'),
        ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers')
    ) AS manual(product_category_name, product_category_name_english)
)
SELECT p.product_id,
       p.product_category_name                                   AS category_pt,
       COALESCE(t.product_category_name_english, 'unknown')      AS category_en,
       p.product_name_lenght                                     AS name_length,
       p.product_description_lenght                              AS description_length,
       p.product_photos_qty                                      AS photos_qty,
       p.product_weight_g                                        AS weight_g,
       p.product_length_cm                                       AS length_cm,
       p.product_height_cm                                       AS height_cm,
       p.product_width_cm                                        AS width_cm
FROM raw.products p
LEFT JOIN translation t ON t.product_category_name = p.product_category_name;
ALTER TABLE analytics.dim_product ADD PRIMARY KEY (product_id);

-- ---------------------------------------------------------------------
-- dim_seller : one row per seller
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_seller AS
SELECT seller_id,
       seller_zip_code_prefix AS zip_code_prefix,
       INITCAP(seller_city)   AS city,
       seller_state           AS state
FROM raw.sellers;
ALTER TABLE analytics.dim_seller ADD PRIMARY KEY (seller_id);

-- ---------------------------------------------------------------------
-- fact_reviews : exactly ONE review per order (latest answer timestamp)
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_reviews AS
SELECT review_id, order_id, review_score,
       review_comment_title, review_comment_message,
       review_creation_date, review_answer_timestamp
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY order_id
               ORDER BY review_answer_timestamp DESC NULLS LAST,
                        review_creation_date    DESC NULLS LAST,
                        review_id
           ) AS rn
    FROM raw.order_reviews r
) x
WHERE rn = 1;
ALTER TABLE analytics.fact_reviews ADD PRIMARY KEY (order_id);

-- ---------------------------------------------------------------------
-- fact_orders : ONE row per order (the main table for Power BI)
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_orders AS
WITH items AS (
    SELECT order_id,
           COUNT(*)           AS items_count,
           SUM(price)         AS items_revenue,
           SUM(freight_value) AS freight_total
    FROM raw.order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           COUNT(*)                  AS payment_rows,
           SUM(payment_value)        AS payment_total,
           MAX(payment_installments) AS max_installments
    FROM raw.order_payments
    GROUP BY order_id
),
main_pay AS (
    SELECT DISTINCT ON (order_id) order_id, payment_type AS main_payment_type
    FROM raw.order_payments
    ORDER BY order_id, payment_value DESC, payment_sequential
),
base AS (
    SELECT o.order_id,
           c.customer_unique_id,
           INITCAP(c.customer_city) AS customer_city,
           c.customer_state,
           o.order_status,
           o.order_purchase_timestamp                  AS purchase_ts,
           o.order_purchase_timestamp::date            AS purchase_date,
           DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
           o.order_approved_at                         AS approved_at,
           o.order_delivered_customer_date             AS delivered_customer_ts,
           o.order_estimated_delivery_date::date       AS estimated_delivery_date,
           COALESCE(i.items_count, 0)                  AS items_count,
           COALESCE(i.items_revenue, 0)                AS items_revenue,
           COALESCE(i.freight_total, 0)                AS freight_total,
           COALESCE(p.payment_rows, 0)                 AS payment_rows,
           COALESCE(p.payment_total, 0)                AS payment_total,
           p.max_installments,
           mp.main_payment_type,
           rv.review_score
    FROM raw.orders o
    JOIN raw.customers c   ON c.customer_id = o.customer_id
    LEFT JOIN items i      ON i.order_id = o.order_id
    LEFT JOIN pay p        ON p.order_id = o.order_id
    LEFT JOIN main_pay mp  ON mp.order_id = o.order_id
    LEFT JOIN analytics.fact_reviews rv ON rv.order_id = o.order_id
)
SELECT b.*,
       (b.order_status NOT IN ('canceled', 'unavailable') AND b.items_count > 0) AS is_valid_order,
       (b.order_status = 'canceled')                                              AS is_canceled,
       (b.max_installments > 1)                                                   AS is_installment_order,
       (b.order_status = 'delivered' AND b.delivered_customer_ts IS NOT NULL)     AS is_delivery_eligible,
       -- delivery metrics are filled only for delivery-eligible orders
       CASE WHEN b.order_status = 'delivered' AND b.delivered_customer_ts IS NOT NULL
            THEN ROUND(EXTRACT(EPOCH FROM (b.delivered_customer_ts - b.purchase_ts)) / 86400.0, 2) END AS delivery_days,
       CASE WHEN b.order_status = 'delivered' AND b.delivered_customer_ts IS NOT NULL
            THEN b.delivered_customer_ts::date - b.estimated_delivery_date END                       AS days_vs_estimate,  -- negative = early
       CASE WHEN b.order_status = 'delivered' AND b.delivered_customer_ts IS NOT NULL
            THEN (b.delivered_customer_ts::date > b.estimated_delivery_date) END                     AS is_late,
       CASE WHEN b.order_status = 'delivered' AND b.delivered_customer_ts IS NOT NULL
            THEN GREATEST(b.delivered_customer_ts::date - b.estimated_delivery_date, 0) END          AS delay_days         -- 0 when on time
FROM base b;
ALTER TABLE analytics.fact_orders ADD PRIMARY KEY (order_id);
CREATE INDEX idx_fo_customer ON analytics.fact_orders(customer_unique_id);
CREATE INDEX idx_fo_month    ON analytics.fact_orders(purchase_month);

-- ---------------------------------------------------------------------
-- fact_order_items : ONE row per item line (product/seller analysis)
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_order_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       i.shipping_limit_date,
       i.price,
       i.freight_value,
       o.purchase_date,
       o.purchase_month,
       o.order_status,
       o.is_valid_order
FROM raw.order_items i
JOIN analytics.fact_orders o ON o.order_id = i.order_id;
ALTER TABLE analytics.fact_order_items ADD PRIMARY KEY (order_id, order_item_id);
CREATE INDEX idx_foi_product ON analytics.fact_order_items(product_id);
CREATE INDEX idx_foi_seller  ON analytics.fact_order_items(seller_id);

-- ---------------------------------------------------------------------
-- fact_payments : ONE row per payment line (payment type analysis)
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_payments AS
SELECT p.order_id,
       p.payment_sequential,
       p.payment_type,
       p.payment_installments,
       p.payment_value,
       o.purchase_month,
       o.order_status
FROM raw.order_payments p
JOIN analytics.fact_orders o ON o.order_id = p.order_id;
ALTER TABLE analytics.fact_payments ADD PRIMARY KEY (order_id, payment_sequential);

-- ---------------------------------------------------------------------
-- dim_customer : one row per real customer (customer_unique_id)
-- Counts VALID orders only. City/state come from the latest order.
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_customer AS
SELECT customer_unique_id,
       (ARRAY_AGG(customer_state ORDER BY purchase_ts DESC))[1] AS state,
       (ARRAY_AGG(customer_city  ORDER BY purchase_ts DESC))[1] AS city,
       COUNT(*)                                                 AS total_orders_all,
       COUNT(*) FILTER (WHERE is_valid_order)                   AS valid_orders,
       MIN(purchase_date) FILTER (WHERE is_valid_order)         AS first_valid_order_date,
       MAX(purchase_date) FILTER (WHERE is_valid_order)         AS last_valid_order_date,
       SUM(items_revenue) FILTER (WHERE is_valid_order)         AS total_spend,
       (COUNT(*) FILTER (WHERE is_valid_order) > 1)             AS is_repeat_customer
FROM analytics.fact_orders
GROUP BY customer_unique_id;
ALTER TABLE analytics.dim_customer ADD PRIMARY KEY (customer_unique_id);

-- Foreign keys inside analytics (documents the star schema)
ALTER TABLE analytics.fact_orders      ADD FOREIGN KEY (customer_unique_id) REFERENCES analytics.dim_customer(customer_unique_id);
ALTER TABLE analytics.fact_order_items ADD FOREIGN KEY (product_id)         REFERENCES analytics.dim_product(product_id);
ALTER TABLE analytics.fact_order_items ADD FOREIGN KEY (seller_id)          REFERENCES analytics.dim_seller(seller_id);

-- ---------------------------------------------------------------------
-- VERIFICATION: every status must be OK
-- ---------------------------------------------------------------------
SELECT check_name, expected, actual,
       CASE WHEN expected = actual THEN 'OK' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'fact_orders rows = raw orders' AS check_name, (SELECT COUNT(*) FROM raw.orders)::numeric AS expected, (SELECT COUNT(*) FROM analytics.fact_orders)::numeric AS actual
    UNION ALL SELECT 'fact_order_items rows = raw items', (SELECT COUNT(*) FROM raw.order_items), (SELECT COUNT(*) FROM analytics.fact_order_items)
    UNION ALL SELECT 'fact_payments rows = raw payments', (SELECT COUNT(*) FROM raw.order_payments), (SELECT COUNT(*) FROM analytics.fact_payments)
    UNION ALL SELECT 'fact_reviews rows = orders with a review', (SELECT COUNT(DISTINCT order_id) FROM raw.order_reviews), (SELECT COUNT(*) FROM analytics.fact_reviews)
    UNION ALL SELECT 'dim_product rows = raw products', (SELECT COUNT(*) FROM raw.products), (SELECT COUNT(*) FROM analytics.dim_product)
    UNION ALL SELECT 'dim_seller rows = raw sellers', (SELECT COUNT(*) FROM raw.sellers), (SELECT COUNT(*) FROM analytics.dim_seller)
    UNION ALL SELECT 'dim_customer rows = unique customers', (SELECT COUNT(DISTINCT customer_unique_id) FROM raw.customers), (SELECT COUNT(*) FROM analytics.dim_customer)
    UNION ALL SELECT 'item price total unchanged', (SELECT SUM(price) FROM raw.order_items), (SELECT SUM(items_revenue) FROM analytics.fact_orders)
    UNION ALL SELECT 'freight total unchanged', (SELECT SUM(freight_value) FROM raw.order_items), (SELECT SUM(freight_total) FROM analytics.fact_orders)
    UNION ALL SELECT 'payment total unchanged', (SELECT SUM(payment_value) FROM raw.order_payments), (SELECT SUM(payment_total) FROM analytics.fact_orders)
    UNION ALL SELECT 'products with no english category', 0, (SELECT COUNT(*) FROM analytics.dim_product WHERE category_en IS NULL)
    UNION ALL SELECT 'delivery-eligible orders', 96470, (SELECT COUNT(*) FROM analytics.fact_orders WHERE is_delivery_eligible)
) v;

-- Key business numbers produced by the cleaned layer (for your notes)
SELECT COUNT(*) FILTER (WHERE is_valid_order)                               AS valid_orders,
       ROUND(SUM(items_revenue) FILTER (WHERE is_valid_order), 2)           AS revenue_valid_orders,
       ROUND(SUM(items_revenue) FILTER (WHERE is_valid_order)
             / COUNT(*) FILTER (WHERE is_valid_order), 2)                   AS avg_order_value,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE is_valid_order)     AS unique_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_delivery_eligible AND NOT is_late)
             / COUNT(*) FILTER (WHERE is_delivery_eligible), 2)             AS on_time_delivery_pct,
       ROUND(AVG(review_score) FILTER (WHERE is_valid_order), 2)            AS avg_review_score
FROM analytics.fact_orders;
-- =====================================================================
-- CommerceIQ | 03_data_quality_checks.sql
-- READ-ONLY. Changes nothing. Measures every data issue found while
-- profiling the Olist CSVs, so each cleaning decision in Step 04 has
-- evidence behind it.
-- Run: psql -U postgres -d commerceiq -P pager=off -f sql/03_data_quality_checks.sql
-- =====================================================================

\connect commerceiq

-- ---------------------------------------------------------------------
-- A. DATA QUALITY SUMMARY  (one row per check)
-- ---------------------------------------------------------------------
SELECT check_group, check_name, issue_count, handling
FROM (
    -- ---------- Granularity: where a careless JOIN duplicates rows ----------
    SELECT 1 AS grp, 'Granularity' AS check_group, 'orders with more than 1 item row' AS check_name,
           (SELECT COUNT(*) FROM (SELECT order_id FROM raw.order_items GROUP BY order_id HAVING COUNT(*) > 1) x) AS issue_count,
           'Aggregate items to order level before joining' AS handling
    UNION ALL SELECT 1, 'Granularity', 'orders with more than 1 payment row',
           (SELECT COUNT(*) FROM (SELECT order_id FROM raw.order_payments GROUP BY order_id HAVING COUNT(*) > 1) x),
           'SUM(payment_value) per order before joining'
    UNION ALL SELECT 1, 'Granularity', 'orders with more than 1 review',
           (SELECT COUNT(*) FROM (SELECT order_id FROM raw.order_reviews GROUP BY order_id HAVING COUNT(*) > 1) x),
           'Keep 1 review per order (latest answer timestamp)'
    UNION ALL SELECT 1, 'Granularity', 'review_id values used on more than 1 row',
           (SELECT COUNT(*) FROM (SELECT review_id FROM raw.order_reviews GROUP BY review_id HAVING COUNT(*) > 1) x),
           'review_id is not a key; use (review_id, order_id)'
    UNION ALL SELECT 1, 'Granularity', 'customers (customer_unique_id) with more than 1 customer_id',
           (SELECT COUNT(*) FROM (SELECT customer_unique_id FROM raw.customers GROUP BY customer_unique_id HAVING COUNT(*) > 1) x),
           'Count people with customer_unique_id, never customer_id'

    -- ---------- Coverage: orders missing child records ----------
    UNION ALL SELECT 2, 'Coverage', 'orders without any item',
           (SELECT COUNT(*) FROM raw.orders o WHERE NOT EXISTS (SELECT 1 FROM raw.order_items i WHERE i.order_id = o.order_id)),
           'Excluded from revenue; decide if counted in Total Orders'
    UNION ALL SELECT 2, 'Coverage', 'orders without any payment',
           (SELECT COUNT(*) FROM raw.orders o WHERE NOT EXISTS (SELECT 1 FROM raw.order_payments p WHERE p.order_id = o.order_id)),
           'Left join; payment metrics ignore them'
    UNION ALL SELECT 2, 'Coverage', 'orders without any review',
           (SELECT COUNT(*) FROM raw.orders o WHERE NOT EXISTS (SELECT 1 FROM raw.order_reviews r WHERE r.order_id = o.order_id)),
           'Left join; review metrics ignore them'

    -- ---------- Missing values ----------
    UNION ALL SELECT 3, 'Missing values', 'orders with no approved_at',
           (SELECT COUNT(*) FROM raw.orders WHERE order_approved_at IS NULL),
           'Keep; not used in KPIs'
    UNION ALL SELECT 3, 'Missing values', 'delivered orders with no delivered_customer_date',
           (SELECT COUNT(*) FROM raw.orders WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL),
           'Exclude from delivery KPIs'
    UNION ALL SELECT 3, 'Missing values', 'non-delivered orders that have a delivered_customer_date',
           (SELECT COUNT(*) FROM raw.orders WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL),
           'Exclude from delivery KPIs (status is not delivered)'
    UNION ALL SELECT 3, 'Missing values', 'products with no category',
           (SELECT COUNT(*) FROM raw.products WHERE product_category_name IS NULL),
           'Label as "unknown"'
    UNION ALL SELECT 3, 'Missing values', 'products with no weight or dimensions',
           (SELECT COUNT(*) FROM raw.products WHERE product_weight_g IS NULL OR product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL),
           'Keep; not used in KPIs'

    -- ---------- Invalid or inconsistent values ----------
    UNION ALL SELECT 4, 'Invalid values', 'payments with value <= 0',
           (SELECT COUNT(*) FROM raw.order_payments WHERE payment_value <= 0),
           'Flag; zero-value rows add nothing to payment totals'
    UNION ALL SELECT 4, 'Invalid values', 'payments with installments = 0',
           (SELECT COUNT(*) FROM raw.order_payments WHERE payment_installments = 0),
           'Installment rate uses installments > 1, so unaffected'
    UNION ALL SELECT 4, 'Invalid values', 'payments with type not_defined',
           (SELECT COUNT(*) FROM raw.order_payments WHERE payment_type = 'not_defined'),
           'Keep as its own type'
    UNION ALL SELECT 4, 'Invalid values', 'items with price <= 0',
           (SELECT COUNT(*) FROM raw.order_items WHERE price <= 0),
           'None expected'
    UNION ALL SELECT 4, 'Invalid values', 'delivered before purchase',
           (SELECT COUNT(*) FROM raw.orders WHERE order_delivered_customer_date < order_purchase_timestamp),
           'None expected'
    UNION ALL SELECT 4, 'Invalid values', 'approved before purchase',
           (SELECT COUNT(*) FROM raw.orders WHERE order_approved_at < order_purchase_timestamp),
           'None expected'
    UNION ALL SELECT 4, 'Invalid values', 'handed to carrier after customer delivery',
           (SELECT COUNT(*) FROM raw.orders WHERE order_delivered_carrier_date > order_delivered_customer_date),
           'Flag; keep (customer delivery date drives delivery KPIs)'
    UNION ALL SELECT 4, 'Invalid values', 'orders where payment total <> items price + freight (> 0.01)',
           (SELECT COUNT(*) FROM (
                SELECT i.order_id
                FROM (SELECT order_id, SUM(price + freight_value) AS total FROM raw.order_items GROUP BY order_id) i
                JOIN (SELECT order_id, SUM(payment_value) AS paid FROM raw.order_payments GROUP BY order_id) p USING (order_id)
                WHERE ABS(p.paid - i.total) > 0.01) x),
           'Revenue = item price; never use payment_value as revenue'

    -- ---------- Reference data ----------
    UNION ALL SELECT 5, 'Reference data', 'product categories missing from translation table',
           (SELECT COUNT(DISTINCT product_category_name) FROM raw.products p
            WHERE product_category_name IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM raw.product_category_translation t WHERE t.product_category_name = p.product_category_name)),
           'Add the 2 missing translations in Step 04'
    UNION ALL SELECT 5, 'Reference data', 'order items with no usable English category',
           (SELECT COUNT(*) FROM raw.order_items i
            JOIN raw.products p USING (product_id)
            LEFT JOIN raw.product_category_translation t ON t.product_category_name = p.product_category_name
            WHERE t.product_category_name_english IS NULL),
           'COALESCE to "unknown"'

    -- ---------- Time coverage ----------
    UNION ALL SELECT 6, 'Time coverage', 'orders outside the complete period 2017-01 to 2018-08',
           (SELECT COUNT(*) FROM raw.orders
            WHERE order_purchase_timestamp < '2017-01-01' OR order_purchase_timestamp >= '2018-09-01'),
           'Show trends for 2017-01..2018-08 only, or add a note'
) q
ORDER BY grp, check_name;

-- ---------------------------------------------------------------------
-- B. ORDER STATUS DISTRIBUTION
-- ---------------------------------------------------------------------
SELECT order_status,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM raw.orders
GROUP BY order_status
ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- C. KPI DEFINITION CHECK: on-time delivery
-- Eligible = status 'delivered' AND delivered_customer_date IS NOT NULL.
-- Estimated dates are always 00:00:00, so we compare at DATE level.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS eligible_orders,
       COUNT(*) FILTER (WHERE order_delivered_customer_date::date >  order_estimated_delivery_date::date) AS late_by_date,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date::date >  order_estimated_delivery_date::date) / COUNT(*), 2) AS late_rate_by_date_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date        >  order_estimated_delivery_date)        / COUNT(*), 2) AS late_rate_by_timestamp_pct
FROM raw.orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- ---------------------------------------------------------------------
-- D. KPI DEFINITION CHECK: revenue components
-- ---------------------------------------------------------------------
SELECT (SELECT SUM(price)         FROM raw.order_items)    AS item_price_total,
       (SELECT SUM(freight_value) FROM raw.order_items)    AS freight_total,
       (SELECT SUM(payment_value) FROM raw.order_payments) AS payment_total;
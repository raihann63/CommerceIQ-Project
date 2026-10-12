-- =====================================================================
-- CommerceIQ | 06_create_views.sql
-- Power BI-ready views on top of the cleaned analytics tables.
-- Safe to re-run.
-- Run: psql -U postgres -d commerceiq -P pager=off -f sql/06_create_views.sql
--
-- Power BI star schema uses the TABLES:
--   fact_orders, fact_order_items, fact_payments, fact_reviews,
--   dim_customer, dim_product, dim_seller
-- The views below are (a) pre-aggregated summaries for validation and
-- quick visuals, and (b) vw_kpi_summary, the single source of truth that
-- the Power BI DAX measures must reproduce (Step 07 testing).
-- Percent columns are 0-100 numbers rounded to 2 decimals.
-- =====================================================================

\connect commerceiq

DROP VIEW IF EXISTS analytics.vw_kpi_summary          CASCADE;
DROP VIEW IF EXISTS analytics.vw_monthly_kpis         CASCADE;
DROP VIEW IF EXISTS analytics.vw_category_performance CASCADE;
DROP VIEW IF EXISTS analytics.vw_seller_performance   CASCADE;
DROP VIEW IF EXISTS analytics.vw_state_performance    CASCADE;
DROP VIEW IF EXISTS analytics.vw_review_by_delay      CASCADE;
DROP VIEW IF EXISTS analytics.vw_payment_summary      CASCADE;
DROP VIEW IF EXISTS analytics.vw_order_details        CASCADE;

-- ---------------------------------------------------------------------
-- 1. Headline KPIs (one row)
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_kpi_summary AS
SELECT
    ROUND(SUM(items_revenue) FILTER (WHERE is_valid_order), 2)                     AS total_revenue,
    ROUND(SUM(freight_total) FILTER (WHERE is_valid_order), 2)                     AS total_freight,
    COUNT(*) FILTER (WHERE is_valid_order)                                         AS total_orders,
    ROUND(SUM(items_revenue) FILTER (WHERE is_valid_order)
          / COUNT(*) FILTER (WHERE is_valid_order), 2)                             AS avg_order_value,
    COUNT(DISTINCT customer_unique_id) FILTER (WHERE is_valid_order)               AS unique_customers,
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat_customer)
            / COUNT(*) FILTER (WHERE valid_orders > 0), 2) FROM analytics.dim_customer) AS repeat_customer_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_delivery_eligible AND NOT is_late)
          / COUNT(*) FILTER (WHERE is_delivery_eligible), 2)                       AS on_time_delivery_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_delivery_eligible AND is_late)
          / COUNT(*) FILTER (WHERE is_delivery_eligible), 2)                       AS late_delivery_rate_pct,
    ROUND(AVG(delivery_days) FILTER (WHERE is_delivery_eligible), 2)               AS avg_delivery_days,
    ROUND(AVG(delay_days) FILTER (WHERE is_delivery_eligible AND is_late), 2)      AS avg_delay_days_when_late,
    ROUND(AVG(review_score) FILTER (WHERE is_valid_order), 2)                      AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_valid_order AND review_score <= 2)
          / COUNT(*) FILTER (WHERE is_valid_order AND review_score IS NOT NULL), 2) AS low_rating_rate_pct,
    COUNT(*) FILTER (WHERE is_valid_order AND review_score IS NOT NULL)            AS total_reviews,
    ROUND(SUM(payment_total) FILTER (WHERE is_valid_order), 2)                     AS total_payment_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_canceled) / COUNT(*), 2)               AS cancellation_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_valid_order AND is_installment_order)
          / COUNT(*) FILTER (WHERE is_valid_order AND max_installments IS NOT NULL), 2) AS installment_usage_rate_pct
FROM analytics.fact_orders;

-- ---------------------------------------------------------------------
-- 2. Monthly KPIs with growth and running total
-- is_complete_period = TRUE for 2017-01 to 2018-08 (use as a filter)
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_monthly_kpis AS
WITH monthly AS (
    SELECT purchase_month,
           COUNT(*)           AS orders,
           SUM(items_revenue) AS revenue
    FROM analytics.fact_orders
    WHERE is_valid_order
    GROUP BY purchase_month
)
SELECT purchase_month,
       (purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01')   AS is_complete_period,
       orders,
       ROUND(revenue, 2)                                                  AS revenue,
       ROUND(revenue / orders, 2)                                         AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w) / NULLIF(LAG(revenue) OVER w, 0), 2) AS revenue_mom_pct,
       ROUND(SUM(revenue) OVER (ORDER BY purchase_month), 2)              AS running_revenue
FROM monthly
WINDOW w AS (ORDER BY purchase_month);

-- ---------------------------------------------------------------------
-- 3. Category performance
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_category_performance AS
WITH cat AS (
    SELECT p.category_en,
           SUM(i.price)               AS revenue,
           COUNT(*)                   AS units_sold,
           COUNT(DISTINCT i.order_id) AS orders
    FROM analytics.fact_order_items i
    JOIN analytics.dim_product p USING (product_id)
    WHERE i.is_valid_order
    GROUP BY p.category_en
),
rating AS (
    SELECT oc.category_en, ROUND(AVG(o.review_score), 2) AS avg_review
    FROM (SELECT DISTINCT i.order_id, p.category_en
          FROM analytics.fact_order_items i
          JOIN analytics.dim_product p USING (product_id)
          WHERE i.is_valid_order) oc
    JOIN analytics.fact_orders o USING (order_id)
    GROUP BY oc.category_en
)
SELECT RANK() OVER (ORDER BY c.revenue DESC)                          AS revenue_rank,
       c.category_en, c.units_sold, c.orders,
       ROUND(c.revenue, 2)                                            AS revenue,
       ROUND(c.revenue / c.units_sold, 2)                             AS avg_item_price,
       ROUND(100.0 * c.revenue / SUM(c.revenue) OVER (), 2)           AS revenue_pct,
       r.avg_review
FROM cat c
LEFT JOIN rating r USING (category_en);

-- ---------------------------------------------------------------------
-- 4. Seller performance
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_seller_performance AS
WITH seller_orders AS (
    SELECT seller_id, order_id, SUM(price) AS revenue, COUNT(*) AS units
    FROM analytics.fact_order_items
    WHERE is_valid_order
    GROUP BY seller_id, order_id
),
stats AS (
    SELECT so.seller_id,
           SUM(so.revenue)                                   AS revenue,
           SUM(so.units)                                     AS units_sold,
           COUNT(*)                                          AS orders,
           COUNT(*) FILTER (WHERE o.is_delivery_eligible)    AS delivered_orders,
           COUNT(*) FILTER (WHERE o.is_late)                 AS late_orders,
           AVG(o.review_score)                               AS avg_review
    FROM seller_orders so
    JOIN analytics.fact_orders o USING (order_id)
    GROUP BY so.seller_id
)
SELECT RANK() OVER (ORDER BY s.revenue DESC)                 AS revenue_rank,
       s.seller_id, d.city, d.state,
       ROUND(s.revenue, 2)                                   AS revenue,
       s.orders, s.units_sold, s.delivered_orders, s.late_orders,
       ROUND(100.0 * s.late_orders / NULLIF(s.delivered_orders, 0), 2) AS late_rate_pct,
       ROUND(s.avg_review, 2)                                AS avg_review
FROM stats s
JOIN analytics.dim_seller d USING (seller_id);

-- ---------------------------------------------------------------------
-- 5. Customer-state performance (revenue + delivery + satisfaction)
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_state_performance AS
SELECT customer_state,
       COUNT(*) FILTER (WHERE is_valid_order)                                 AS valid_orders,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE is_valid_order)       AS customers,
       ROUND(SUM(items_revenue) FILTER (WHERE is_valid_order), 2)             AS revenue,
       COUNT(*) FILTER (WHERE is_delivery_eligible)                           AS delivered_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_delivery_eligible AND is_late)
             / NULLIF(COUNT(*) FILTER (WHERE is_delivery_eligible), 0), 2)    AS late_rate_pct,
       ROUND(AVG(delivery_days) FILTER (WHERE is_delivery_eligible), 1)       AS avg_delivery_days,
       ROUND(AVG(delay_days) FILTER (WHERE is_delivery_eligible AND is_late), 1) AS avg_delay_days_when_late,
       ROUND(AVG(review_score) FILTER (WHERE is_valid_order), 2)              AS avg_review
FROM analytics.fact_orders
GROUP BY customer_state;

-- ---------------------------------------------------------------------
-- 6. Review score by delivery delay bucket
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_review_by_delay AS
SELECT CASE WHEN days_vs_estimate <= 0 THEN '1. On time or early'
            WHEN days_vs_estimate <= 3 THEN '2. 1-3 days late'
            WHEN days_vs_estimate <= 7 THEN '3. 4-7 days late'
            ELSE                            '4. 8+ days late' END      AS delivery_bucket,
       COUNT(*)                                                         AS orders,
       ROUND(AVG(review_score), 2)                                      AS avg_review,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 2) AS low_rating_pct
FROM analytics.fact_orders
WHERE is_delivery_eligible AND review_score IS NOT NULL
GROUP BY 1;

-- ---------------------------------------------------------------------
-- 7. Payment summary by payment type (valid orders only)
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_payment_summary AS
SELECT p.payment_type,
       COUNT(DISTINCT p.order_id)                                       AS orders,
       ROUND(SUM(p.payment_value), 2)                                   AS payment_value,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 2) AS value_pct,
       ROUND(AVG(p.payment_installments), 2)                            AS avg_installments
FROM analytics.fact_payments p
JOIN analytics.fact_orders o USING (order_id)
WHERE o.is_valid_order
GROUP BY p.payment_type;

-- ---------------------------------------------------------------------
-- 8. Order-level detail table (Page 8 "Details")
-- ---------------------------------------------------------------------
CREATE VIEW analytics.vw_order_details AS
SELECT order_id, purchase_date, customer_unique_id, customer_city, customer_state,
       order_status, is_valid_order, items_count, items_revenue, freight_total,
       payment_total, main_payment_type, max_installments, review_score,
       estimated_delivery_date, delivered_customer_ts::date AS delivered_date,
       delivery_days, days_vs_estimate, is_late
FROM analytics.fact_orders;

-- ---------------------------------------------------------------------
-- Check: all 8 views exist and return rows
-- ---------------------------------------------------------------------
SELECT 'vw_kpi_summary' AS view_name, COUNT(*) AS rows FROM analytics.vw_kpi_summary
UNION ALL SELECT 'vw_monthly_kpis',          COUNT(*) FROM analytics.vw_monthly_kpis
UNION ALL SELECT 'vw_category_performance',  COUNT(*) FROM analytics.vw_category_performance
UNION ALL SELECT 'vw_seller_performance',    COUNT(*) FROM analytics.vw_seller_performance
UNION ALL SELECT 'vw_state_performance',     COUNT(*) FROM analytics.vw_state_performance
UNION ALL SELECT 'vw_review_by_delay',       COUNT(*) FROM analytics.vw_review_by_delay
UNION ALL SELECT 'vw_payment_summary',       COUNT(*) FROM analytics.vw_payment_summary
UNION ALL SELECT 'vw_order_details',         COUNT(*) FROM analytics.vw_order_details;

-- The headline KPIs that Power BI must match (transposed for readability)
SELECT k.key AS kpi, k.value
FROM analytics.vw_kpi_summary s,
     LATERAL jsonb_each_text(to_jsonb(s)) AS k(key, value);
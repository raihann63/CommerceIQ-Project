-- =====================================================================
-- CommerceIQ | 05_business_analysis.sql
-- READ-ONLY business questions answered from the cleaned analytics layer.
-- Run: psql -U postgres -d commerceiq -P pager=off -f sql/05_business_analysis.sql
-- Uses: JOIN, GROUP BY, CASE, FILTER, CTEs, window functions
--       (RANK, ROW_NUMBER, LAG, LEAD, running totals, NTILE).
-- Valid orders only unless stated. Trend queries use the complete
-- period 2017-01 to 2018-08 (other months have too few orders).
-- =====================================================================

\connect commerceiq

-- ---------------------------------------------------------------------
-- Q1. Monthly revenue, orders, AOV, month-over-month growth, running total
-- ---------------------------------------------------------------------
\echo '--- Q1: Monthly trend'
WITH monthly AS (
    SELECT purchase_month,
           COUNT(*)           AS orders,
           SUM(items_revenue) AS revenue
    FROM analytics.fact_orders
    WHERE is_valid_order
      AND purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
    GROUP BY purchase_month
)
SELECT purchase_month,
       orders,
       ROUND(revenue, 2)                                          AS revenue,
       ROUND(revenue / orders, 2)                                 AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w)
             / NULLIF(LAG(revenue) OVER w, 0), 1)                 AS revenue_mom_pct,
       ROUND(SUM(revenue) OVER (ORDER BY purchase_month), 2)      AS running_revenue
FROM monthly
WINDOW w AS (ORDER BY purchase_month)
ORDER BY purchase_month;

-- ---------------------------------------------------------------------
-- Q2. Category revenue ranking with Pareto (cumulative share)
-- ---------------------------------------------------------------------
\echo '--- Q2: Top 15 categories'
WITH cat AS (
    SELECT p.category_en,
           SUM(i.price)                AS revenue,
           COUNT(*)                    AS units,
           COUNT(DISTINCT i.order_id)  AS orders
    FROM analytics.fact_order_items i
    JOIN analytics.dim_product p USING (product_id)
    WHERE i.is_valid_order
    GROUP BY p.category_en
)
SELECT RANK() OVER (ORDER BY revenue DESC)                              AS rnk,
       category_en, units, orders,
       ROUND(revenue, 2)                                                AS revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)                 AS revenue_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC)
             / SUM(revenue) OVER (), 2)                                 AS cumulative_pct
FROM cat
ORDER BY rnk
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q3. Top 10 sellers: revenue, orders, late rate, review score
-- (aggregated at seller-order level first to avoid multi-item duplication)
-- ---------------------------------------------------------------------
\echo '--- Q3: Top 10 sellers'
WITH seller_orders AS (
    SELECT i.seller_id, i.order_id, SUM(i.price) AS revenue
    FROM analytics.fact_order_items i
    WHERE i.is_valid_order
    GROUP BY i.seller_id, i.order_id
),
seller_stats AS (
    SELECT so.seller_id,
           SUM(so.revenue)                                              AS revenue,
           COUNT(*)                                                     AS orders,
           COUNT(*) FILTER (WHERE o.is_delivery_eligible)               AS delivered_orders,
           COUNT(*) FILTER (WHERE o.is_late)                            AS late_orders,
           AVG(o.review_score)                                          AS avg_review
    FROM seller_orders so
    JOIN analytics.fact_orders o USING (order_id)
    GROUP BY so.seller_id
)
SELECT RANK() OVER (ORDER BY s.revenue DESC)                            AS rnk,
       s.seller_id, d.state, s.orders,
       ROUND(s.revenue, 2)                                              AS revenue,
       ROUND(100.0 * s.late_orders / NULLIF(s.delivered_orders, 0), 2)  AS late_rate_pct,
       ROUND(s.avg_review, 2)                                           AS avg_review
FROM seller_stats s
JOIN analytics.dim_seller d USING (seller_id)
ORDER BY rnk
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q4. Seller concentration: how much revenue do the top 10% sellers earn?
-- ---------------------------------------------------------------------
\echo '--- Q4: Seller concentration'
WITH seller_rev AS (
    SELECT seller_id, SUM(price) AS revenue
    FROM analytics.fact_order_items
    WHERE is_valid_order
    GROUP BY seller_id
),
ranked AS (
    SELECT revenue, NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM seller_rev
)
SELECT decile,
       COUNT(*)                                              AS sellers,
       ROUND(SUM(revenue), 2)                                AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2) AS revenue_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- ---------------------------------------------------------------------
-- Q5. Delivery performance by customer state
-- ---------------------------------------------------------------------
\echo '--- Q5: Delivery by state (worst late rate first)'
SELECT customer_state,
       COUNT(*)                                              AS delivered_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 2) AS late_rate_pct,
       ROUND(AVG(delivery_days), 1)                          AS avg_delivery_days,
       ROUND(AVG(delay_days) FILTER (WHERE is_late), 1)      AS avg_delay_when_late,
       ROUND(AVG(review_score), 2)                           AS avg_review
FROM analytics.fact_orders
WHERE is_delivery_eligible
GROUP BY customer_state
HAVING COUNT(*) >= 200
ORDER BY late_rate_pct DESC;

-- ---------------------------------------------------------------------
-- Q6. KEY INSIGHT: does a late delivery hurt the review score?
-- ---------------------------------------------------------------------
\echo '--- Q6: Review score vs delivery delay'
SELECT CASE WHEN days_vs_estimate <= 0 THEN '1. On time or early'
            WHEN days_vs_estimate <= 3 THEN '2. 1-3 days late'
            WHEN days_vs_estimate <= 7 THEN '3. 4-7 days late'
            ELSE                            '4. 8+ days late' END AS delivery_bucket,
       COUNT(*)                                                    AS orders,
       ROUND(AVG(review_score), 2)                                 AS avg_review,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 1) AS low_rating_pct
FROM analytics.fact_orders
WHERE is_delivery_eligible AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q7. Review score distribution
-- ---------------------------------------------------------------------
\echo '--- Q7: Review distribution'
SELECT review_score,
       COUNT(*)                                                    AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct
FROM analytics.fact_orders
WHERE is_valid_order AND review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- ---------------------------------------------------------------------
-- Q8. New vs repeat orders per month (ROW_NUMBER per customer)
-- ---------------------------------------------------------------------
\echo '--- Q8: New vs repeat orders'
WITH numbered AS (
    SELECT customer_unique_id, purchase_month,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts) AS order_no
    FROM analytics.fact_orders
    WHERE is_valid_order
)
SELECT purchase_month,
       COUNT(*) FILTER (WHERE order_no = 1)  AS new_customer_orders,
       COUNT(*) FILTER (WHERE order_no > 1)  AS repeat_customer_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_no > 1) / COUNT(*), 2) AS repeat_share_pct
FROM numbered
WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY purchase_month
ORDER BY purchase_month;

-- ---------------------------------------------------------------------
-- Q9. Purchase frequency and time to second order (LEAD)
-- ---------------------------------------------------------------------
\echo '--- Q9a: Purchase frequency'
SELECT valid_orders AS orders_per_customer,
       COUNT(*)     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM analytics.dim_customer
WHERE valid_orders > 0
GROUP BY valid_orders
ORDER BY valid_orders;

\echo '--- Q9b: Days between first and second order (repeat customers)'
WITH ordered AS (
    SELECT customer_unique_id, purchase_date,
           ROW_NUMBER() OVER w AS order_no,
           LEAD(purchase_date) OVER w AS next_order_date
    FROM analytics.fact_orders
    WHERE is_valid_order
    WINDOW w AS (PARTITION BY customer_unique_id ORDER BY purchase_ts)
)
SELECT COUNT(*)                                                       AS repeat_customers,
       ROUND(AVG(next_order_date - purchase_date), 1)                 AS avg_days_to_second_order,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY next_order_date - purchase_date) AS median_days_to_second_order,
       ROUND(100.0 * COUNT(*) FILTER (WHERE next_order_date - purchase_date <= 90) / COUNT(*), 1) AS pct_within_90_days
FROM ordered
WHERE order_no = 1 AND next_order_date IS NOT NULL;

-- ---------------------------------------------------------------------
-- Q10. Payments: type mix and installment usage
-- ---------------------------------------------------------------------
\echo '--- Q10a: Payment type mix'
SELECT payment_type,
       COUNT(DISTINCT order_id)                                    AS orders,
       ROUND(SUM(payment_value), 2)                                AS payment_value,
       ROUND(100.0 * SUM(payment_value) / SUM(SUM(payment_value)) OVER (), 2) AS value_pct
FROM analytics.fact_payments
GROUP BY payment_type
ORDER BY payment_value DESC;

\echo '--- Q10b: Installment usage (valid orders)'
SELECT COUNT(*)                                                    AS valid_orders,
       COUNT(*) FILTER (WHERE is_installment_order)                AS installment_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_installment_order) / COUNT(*), 2) AS installment_rate_pct
FROM analytics.fact_orders
WHERE is_valid_order AND max_installments IS NOT NULL;

-- ---------------------------------------------------------------------
-- Q11. Cancellation rate by month
-- ---------------------------------------------------------------------
\echo '--- Q11: Cancellation rate by month'
SELECT purchase_month,
       COUNT(*)                                                    AS orders,
       COUNT(*) FILTER (WHERE is_canceled)                         AS canceled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_canceled) / COUNT(*), 2) AS cancellation_rate_pct
FROM analytics.fact_orders
WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY purchase_month
ORDER BY purchase_month;

-- ---------------------------------------------------------------------
-- Q12. Revenue by customer state with share
-- ---------------------------------------------------------------------
\echo '--- Q12: Revenue by customer state'
SELECT RANK() OVER (ORDER BY SUM(items_revenue) DESC)              AS rnk,
       customer_state,
       COUNT(*)                                                    AS orders,
       ROUND(SUM(items_revenue), 2)                                AS revenue,
       ROUND(100.0 * SUM(items_revenue) / SUM(SUM(items_revenue)) OVER (), 2) AS revenue_pct
FROM analytics.fact_orders
WHERE is_valid_order
GROUP BY customer_state
ORDER BY rnk
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q13. Lowest-rated categories (at least 300 reviewed orders)
-- ---------------------------------------------------------------------
\echo '--- Q13: Rating by category'
WITH order_cat AS (
    SELECT DISTINCT i.order_id, p.category_en
    FROM analytics.fact_order_items i
    JOIN analytics.dim_product p USING (product_id)
    WHERE i.is_valid_order
)
SELECT oc.category_en,
       COUNT(*)                          AS reviewed_orders,
       ROUND(AVG(o.review_score), 2)     AS avg_review,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.review_score <= 2) / COUNT(*), 1) AS low_rating_pct
FROM order_cat oc
JOIN analytics.fact_orders o USING (order_id)
WHERE o.review_score IS NOT NULL
GROUP BY oc.category_en
HAVING COUNT(*) >= 300
ORDER BY avg_review ASC
LIMIT 10;
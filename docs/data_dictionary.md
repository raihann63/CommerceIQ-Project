# Data Dictionary

Two PostgreSQL schemas: `raw` (source CSV files as delivered, never modified) and `analytics` (cleaned tables used by Power BI).
Source: Olist Brazilian E-Commerce Public Dataset (Kaggle).

## Raw schema (8 tables)

| Table | Grain | Key |
|---|---|---|
| raw.customers | one row per order's customer record | customer_id |
| raw.orders | one row per order | order_id |
| raw.order_items | one row per item line | (order_id, order_item_id) |
| raw.order_payments | one row per payment line | (order_id, payment_sequential) |
| raw.order_reviews | one row per review per order | (review_id, order_id) |
| raw.products | one row per product | product_id |
| raw.sellers | one row per seller | seller_id |
| raw.product_category_translation | one row per category | product_category_name |

Notes: `customer_id` is created per order; the real customer is `customer_unique_id`. ZIP prefixes are stored as text to keep leading zeros. Source column names `product_name_lenght` and `product_description_lenght` keep the original misspelling.

## Analytics schema

### analytics.fact_orders (one row per order)

| Column | Meaning |
|---|---|
| order_id | Order key |
| customer_unique_id | Real customer identifier |
| customer_city, customer_state | Delivery location |
| order_status | Order status from source |
| purchase_ts, purchase_date, purchase_month | Purchase time, date and first day of month |
| approved_at, delivered_customer_ts | Approval and customer delivery timestamps |
| estimated_delivery_date | Promised delivery date |
| items_count, items_revenue, freight_total | Items, item price total, freight total |
| payment_rows, payment_total, max_installments | Payment lines, payment total, highest installment count |
| main_payment_type | Payment type with the largest value in the order |
| review_score | One review score per order (latest answer) |
| is_valid_order | Not canceled/unavailable and has at least 1 item |
| is_canceled | Status is canceled |
| is_installment_order | max_installments greater than 1 |
| is_delivery_eligible | Status delivered and delivery date present |
| delivery_days | Days from purchase to delivery (eligible orders only) |
| days_vs_estimate | Delivered date minus estimated date; negative means early |
| is_late | Delivered date is after estimated date |
| delay_days | Days late; 0 when on time |

### analytics.fact_order_items (one row per item line)

order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value, purchase_date, purchase_month, order_status, is_valid_order.

### analytics.fact_payments (one row per payment line)

order_id, payment_sequential, payment_type, payment_installments, payment_value, purchase_month, order_status.

### analytics.fact_reviews (one row per order)

review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp.

### analytics.dim_customer (one row per real customer)

customer_unique_id, state, city (from latest order), total_orders_all, valid_orders, first_valid_order_date, last_valid_order_date, total_spend, is_repeat_customer.

### analytics.dim_product (one row per product)

product_id, category_pt, category_en (unknown when missing), name_length, description_length, photos_qty, weight_g, length_cm, height_cm, width_cm.

### analytics.dim_seller (one row per seller)

seller_id, zip_code_prefix, city, state.

## Views (analytics schema)

| View | Purpose |
|---|---|
| vw_kpi_summary | One-row headline KPIs; the reference for DAX validation |
| vw_monthly_kpis | Monthly orders, revenue, AOV, growth, running total |
| vw_category_performance | Revenue, units, share and rating by category |
| vw_seller_performance | Revenue, orders, late rate and rating by seller |
| vw_state_performance | Revenue, delivery and rating by customer state |
| vw_review_by_delay | Review score by delivery delay bucket |
| vw_payment_summary | Payment value and orders by payment type |
| vw_order_details | Order-level detail table |

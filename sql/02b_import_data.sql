\connect commerceiq

TRUNCATE raw.order_reviews, raw.order_payments, raw.order_items,
         raw.orders, raw.products, raw.sellers, raw.customers,
         raw.product_category_translation;

\copy raw.customers FROM 'data/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy raw.sellers FROM 'data/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy raw.products FROM 'data/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', FORCE_NULL (product_category_name, product_name_lenght, product_description_lenght, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm))

\copy raw.product_category_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy raw.orders FROM 'data/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', FORCE_NULL (order_approved_at, order_delivered_carrier_date, order_delivered_customer_date))

\copy raw.order_items FROM 'data/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy raw.order_payments FROM 'data/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy raw.order_reviews FROM 'data/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', FORCE_NULL (review_comment_title, review_comment_message))

SELECT t.table_name, t.actual_rows, t.expected_rows,
       CASE WHEN t.actual_rows = t.expected_rows THEN 'OK' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'customers'                    AS table_name, COUNT(*) AS actual_rows,  99441 AS expected_rows FROM raw.customers
    UNION ALL SELECT 'sellers',                          COUNT(*),   3095 FROM raw.sellers
    UNION ALL SELECT 'products',                         COUNT(*),  32951 FROM raw.products
    UNION ALL SELECT 'product_category_translation',     COUNT(*),     71 FROM raw.product_category_translation
    UNION ALL SELECT 'orders',                           COUNT(*),  99441 FROM raw.orders
    UNION ALL SELECT 'order_items',                      COUNT(*), 112650 FROM raw.order_items
    UNION ALL SELECT 'order_payments',                   COUNT(*), 103886 FROM raw.order_payments
    UNION ALL SELECT 'order_reviews',                    COUNT(*),  99224 FROM raw.order_reviews
) t
ORDER BY t.table_name;
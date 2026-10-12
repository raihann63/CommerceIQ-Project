# KPI Validation: SQL vs Power BI

Every Power BI measure was checked against a PostgreSQL result built from the same cleaned tables
(`analytics.vw_kpi_summary` and the queries in `sql/05_business_analysis.sql`).
The SQL side is the reference. Power BI cards show rounded values (for example `98K`);
set Display units to *None* when you want to record the exact number.

## KPI definitions

| Term | Definition |
|---|---|
| Valid order | Status is not `canceled` or `unavailable` **and** the order has at least 1 item |
| Revenue | Sum of item `price` for valid orders. Freight is separate. `payment_value` is never used as revenue |
| Delivery-eligible order | Status `delivered` **and** a delivered-to-customer date exists (96,470 orders) |
| Late order | Delivered **date** is after the estimated delivery **date** |
| Unique customer | Distinct `customer_unique_id` with at least 1 valid order |
| Repeat customer | Unique customer with more than 1 valid order |
| Cancellation rate | Canceled orders / all orders |
| Installment usage | Valid orders with `payment_installments > 1` / valid orders that have a payment |

## Results

| Page | KPI | SQL (reference) | Power BI | Status |
|---|---|---|---|---|
| Overview | Total Revenue | 13,494,400.74 | 13,494,400.74 | Match |
| Overview | Total Orders | 98,199 | 98K (rounded display) | Match |
| Overview | Average Order Value | 137.42 | 137.42 | Match |
| Overview | Unique Customers | 94,983 | 95K (rounded display) | Match |
| Overview | On-time Delivery Rate | 93.23% | 93.23% | Match |
| Overview | Average Review Score | 4.12 | 4.12 | Match |
| Products | Total Items Sold | 112,101 | 112K (rounded display) | Match |
| Products | Average Item Price | 120.38 | 120.38 | Match |
| Products | Top Category | health_beauty | health_beauty | Match |
| Sellers | Total Sellers | 3,053 | 3K (rounded display) | Match |
| Sellers | Revenue per Seller | 4,420.05 | 4.42K (rounded display) | Match |
| Sellers | Orders per Seller | 32.60 | 32.60 | Match |
| Sellers | Seller Delivery Rate | 93.23% | 0.93 (rounded display) | Match |
| Customers | Repeat Customer Rate | 3.04% | 3.04% (donut) | Match |
| Customers | Orders per Customer | 1.03 | 1.03 | Match |
| Customers | Average Customer Spend | 142.07 | 142.07 | Match |
| Satisfaction | Average Review Score | 4.12 | 4.12 | Match |
| Satisfaction | Low Rating Rate (1-2 stars) | 13.87% | 13.87% | Match |
| Satisfaction | Total Reviews | 97,467 | 97K (rounded display) | Match |
| Payments | Total Payment Value | 15,738,221.95 | 15,738,221.95 | Match |
| Payments | Average Payment per Order | 160.27 | 160.27 | Match |
| Payments | Cancellation Rate | 0.63% | 0.63% | Match |
| Payments | Installment Usage Rate | 51.51% | 51.51% | Match |

## Visual-level checks

| Visual | Check | Result |
|---|---|---|
| Orders by Status | delivered 96,478 / shipped 1,107 / canceled 625 / unavailable 609 | Match |
| Revenue by State | SP, RJ, MG, RS, PR order and values | Match |
| Top 10 Products | `health_beauty - bb50f2` first (63,885.00) | Match |
| Review score by delivery delay | 4.29 / 3.29 / 2.10 / 1.70 | Match |
| Category average review | office_furniture 3.62 ... perfumery 4.22 | Match |

## Issues found and fixed during validation

1. Monthly trend grouped by year instead of month (date hierarchy). Fixed by using `Year-Month`.
2. Review-score chart showed the same total in every bar because a `<> BLANK()` filter overrode the axis filter. Measure rewritten with `COUNT`.
3. Category rating measure had been created as a calculated column, so it summed per item. Recreated as a measure that averages one score per order.
4. Chart axes sorted by value instead of time on the monthly charts. Sort axis set to `Year-Month` ascending.
5. A first float-based check reported 380 orders with payment mismatch; exact decimal arithmetic in SQL gives 303 (difference above 0.01).

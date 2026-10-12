# Business Insights

Source: Olist Brazilian e-commerce public dataset (orders from 2016-09 to 2018-10), analysed in PostgreSQL and Power BI.
All figures use valid orders and the definitions in `kpi_validation.md`. The dataset has no cost data, so no profit claims are made.
These are observations from historical public data, not conclusions about a real company, and association is not proof of cause.

## 1. Late delivery goes together with much lower ratings
- **Evidence:** average review score is 4.29 for on-time or early orders (9.3% give 1-2 stars), 3.29 for 1-3 days late, 2.10 for 4-7 days late and 1.70 for 8+ days late (79.3% give 1-2 stars).
- **Recommendation:** treat estimated-date accuracy and late-order alerts as a satisfaction lever. Flag orders that pass the estimated date and contact customers before they leave a review.
- **Limit:** late orders also differ by region and product, so this shows a strong association, not proven cause.

## 2. Delays are concentrated in specific regions
- **Evidence:** late rate by customer state is 21.41% in AL, 17.43% in MA and 15.22% in SE, against 4.49% in SP and 4.04% in PR. Average delivery time is 24.5 days in AL and 8.8 days in SP.
- **Recommendation:** review carrier performance and promised delivery dates for the highest-delay states first.

## 3. Revenue depends on a small group of sellers and one state
- **Evidence:** the top 10% of sellers (306) earn 67.50% of revenue; the bottom 50% earn 3.24%. SP contributes 38.27% of revenue, and SP, RJ and MG together 63.36%.
- **Recommendation:** monitor the performance of top-decile sellers closely and track how much revenue sits with them; treat regional expansion as a separate growth question.

## 4. Very few customers return
- **Evidence:** 96.96% of customers placed one valid order; the repeat rate is 3.04% (2,887 customers). Among repeat customers the median time to the second order is 28 days and 68.3% return within 90 days.
- **Recommendation:** if retention is tested, focus on the first 90 days after the first order.
- **Limit:** customers are identified by `customer_unique_id`; the dataset may under-identify returning buyers, so the true repeat rate could be higher.

## 5. Satisfaction is high overall, with weak spots
- **Evidence:** average score 4.12; 58.38% of reviewed orders are 5 stars and 13.87% are 1-2 stars. Among the 15 highest-revenue categories, office_furniture has the lowest average (3.62) and perfumery the highest (4.22).
- **Recommendation:** investigate office_furniture first (delivery time, product quality, expectations) before drawing conclusions.

## 6. Payments run mostly on credit cards and installments
- **Evidence:** credit cards carry 78.47% of payment value, boleto 17.96%. 51.51% of valid orders use installments; credit-card payments average 3.51 installments.
- **Recommendation:** keep credit-card and installment payment flows reliable, since they carry most of the value.

## 7. Demand peaks in November 2017
- **Evidence:** revenue rose 52.1% month over month in 2017-11 (7,421 valid orders, 1,003,862.14), then fell 26.1% in December. Through 2018 monthly orders stayed between about 6,100 and 7,200.
- **Recommendation:** plan stock, seller capacity and delivery capacity for the November peak.

## Limitations
- No cost data: profit and margin cannot be measured.
- 2016 and the last months of 2018 have too few orders; trends use 2017-01 to 2018-08.
- An order can have several payment types and several sellers, so type- and seller-level counts do not add to the order total.
- Customer identity depends on `customer_unique_id`.
- Public dataset from 2016-2018 and a Brazilian market; findings are illustrative.

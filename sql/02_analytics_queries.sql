-- ============================================================================
-- OLIST E-COMMERCE PROJECT — PHASE 2: SQL ANALYTICS QUERIES
-- PostgreSQL. Run ONE query at a time: highlight just that query's text
-- before clicking Run / pressing F5. If you select the whole file and run
-- it, pgAdmin only shows you the result of the LAST query.
--
-- Each query is tagged with the dashboard page it feeds and the business
-- question it answers — these aren't disconnected exercises, they're the
-- analysis behind specific pages of the Power BI dashboard.
-- ============================================================================


-- ============================================================================
-- BONUS — PAGE 1: EXECUTIVE OVERVIEW — headline KPI row
-- Business question: "How is the business performing, at a glance?"
-- One row of numbers: this becomes the top KPI strip of the dashboard.
-- ============================================================================
WITH item_totals AS (
    SELECT
        oi.order_id,
        SUM(oi.price)          AS item_revenue,
        SUM(oi.freight_value)  AS item_freight
    FROM fact_order_items oi
    GROUP BY oi.order_id
)
SELECT
    ROUND(SUM(it.item_revenue)::numeric, 2)                                       AS total_revenue,
    COUNT(DISTINCT fo.order_id)                                                    AS total_orders,
    COUNT(DISTINCT fo.customer_unique_id)                                          AS total_customers,
    ROUND((SUM(it.item_revenue) / COUNT(DISTINCT fo.order_id))::numeric, 2)        AS avg_order_value,
    ROUND(AVG(fo.review_score)::numeric, 2)                                        AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE fo.is_on_time)
        / NULLIF(COUNT(*) FILTER (WHERE fo.is_on_time IS NOT NULL), 0), 1)         AS on_time_delivery_pct,
    ROUND(100.0 * SUM(it.item_freight) / NULLIF(SUM(it.item_revenue), 0), 1)       AS freight_pct_of_revenue
FROM fact_orders fo
JOIN item_totals it ON it.order_id = fo.order_id;


-- ============================================================================
-- QUERY 1 — PAGE 1 & 2 — Monthly revenue trend
-- Business question: Is revenue growing, and when do the peaks/dips happen?
-- ============================================================================
SELECT
    d.year,
    d.month,
    d.month_name,
    ROUND(SUM(oi.price)::numeric, 2) AS monthly_revenue
FROM fact_order_items oi
JOIN fact_orders fo ON fo.order_id = oi.order_id
JOIN dim_date d     ON d.date_key = fo.purchase_date
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- ============================================================================
-- QUERY 2 — PAGE 1 — Monthly order volume
-- Business question: Is order volume growing in line with revenue, or diverging?
-- ============================================================================
SELECT
    d.year,
    d.month,
    d.month_name,
    COUNT(DISTINCT fo.order_id) AS order_count
FROM fact_orders fo
JOIN dim_date d ON d.date_key = fo.purchase_date
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- ============================================================================
-- QUERY 3 — PAGE 1 — Average order value over time
-- Business question: Are customers spending more or less per order over time?
-- ============================================================================
SELECT
    d.year,
    d.month,
    ROUND((SUM(oi.price) / COUNT(DISTINCT fo.order_id))::numeric, 2) AS avg_order_value
FROM fact_order_items oi
JOIN fact_orders fo ON fo.order_id = oi.order_id
JOIN dim_date d     ON d.date_key = fo.purchase_date
GROUP BY d.year, d.month
ORDER BY d.year, d.month;


-- ============================================================================
-- QUERY 4 — PAGE 2 — Revenue by category
-- Business question: Which categories generate the most revenue?
-- ============================================================================
SELECT
    dp.category_name,
    ROUND(SUM(oi.price)::numeric, 2) AS category_revenue,
    COUNT(*)                          AS items_sold
FROM fact_order_items oi
JOIN dim_products dp ON dp.product_id = oi.product_id
GROUP BY dp.category_name
ORDER BY category_revenue DESC;


-- ============================================================================
-- QUERY 5 — PAGE 2 — Top 10 product categories by revenue
-- Business question: What are the top 10 revenue-driving categories?
-- ============================================================================
SELECT
    dp.category_name,
    ROUND(SUM(oi.price)::numeric, 2) AS category_revenue
FROM fact_order_items oi
JOIN dim_products dp ON dp.product_id = oi.product_id
GROUP BY dp.category_name
ORDER BY category_revenue DESC
LIMIT 10;


-- ============================================================================
-- QUERY 6 — PAGE 2 — Revenue contribution % by category
-- Business question: How concentrated is revenue among the top categories?
-- ============================================================================
WITH category_revenue AS (
    SELECT dp.category_name, SUM(oi.price) AS revenue
    FROM fact_order_items oi
    JOIN dim_products dp ON dp.product_id = oi.product_id
    GROUP BY dp.category_name
)
SELECT
    category_name,
    ROUND(revenue::numeric, 2) AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total_revenue
FROM category_revenue
ORDER BY revenue DESC;


-- ============================================================================
-- QUERY 7 — PAGE 3 — Repeat customer rate
-- Business question: What % of customers come back and buy again?
-- NOTE: Olist's real repeat-purchase rate is famously low (commonly cited
-- around 3%). If your number looks small, that's the actual finding —
-- not a bug in your query.
-- ============================================================================
WITH order_counts AS (
    SELECT customer_unique_id, COUNT(*) AS order_count
    FROM fact_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) FILTER (WHERE order_count = 1) AS one_time_customers,
    COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / COUNT(*), 2) AS repeat_customer_pct
FROM order_counts;


-- ============================================================================
-- QUERY 8 — PAGE 3 — Customers with multiple orders (detail)
-- Business question: Who specifically are the repeat customers, and how much
-- have they spent?
-- ============================================================================
SELECT
    customer_unique_id,
    COUNT(*)                              AS order_count,
    ROUND(SUM(total_payment_value)::numeric, 2) AS total_spent
FROM fact_orders
GROUP BY customer_unique_id
HAVING COUNT(*) > 1
ORDER BY order_count DESC, total_spent DESC;


-- ============================================================================
-- QUERY 9 — PAGE 4 — Seller performance
-- Business question: Which sellers drive the most revenue, and how do they
-- perform on reviews and on-time delivery?
-- NOTE: delivery timing in this dataset is recorded per ORDER, not per
-- seller. If an order has items from two sellers, both are credited/blamed
-- for the same delivery outcome — a known limitation of the raw data.
-- ============================================================================
SELECT
    ds.seller_id,
    ds.state,
    COUNT(DISTINCT oi.order_id)      AS orders_fulfilled,
    ROUND(SUM(oi.price)::numeric, 2) AS total_revenue,
    ROUND(AVG(fo.review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE fo.is_on_time)
        / NULLIF(COUNT(*) FILTER (WHERE fo.is_on_time IS NOT NULL), 0), 1) AS on_time_pct
FROM fact_order_items oi
JOIN dim_sellers ds  ON ds.seller_id = oi.seller_id
JOIN fact_orders fo  ON fo.order_id = oi.order_id
GROUP BY ds.seller_id, ds.state
ORDER BY total_revenue DESC;


-- ============================================================================
-- QUERY 10 — PAGE 4 — Average delivery time by customer state
-- Business question: Where do customers wait the longest for their orders?
-- ============================================================================
SELECT
    dc.state AS customer_state,
    ROUND(AVG(fo.delivery_time_days)::numeric, 1) AS avg_delivery_days,
    COUNT(*) AS delivered_orders
FROM fact_orders fo
JOIN dim_customers dc ON dc.customer_unique_id = fo.customer_unique_id
WHERE fo.order_status = 'delivered'
GROUP BY dc.state
ORDER BY avg_delivery_days DESC;


-- ============================================================================
-- QUERY 11 — PAGE 2 — Category ranking (window function)
-- Business question: What's each category's rank by revenue?
-- ============================================================================
SELECT
    dp.category_name,
    ROUND(SUM(oi.price)::numeric, 2) AS revenue,
    RANK() OVER (ORDER BY SUM(oi.price) DESC) AS revenue_rank
FROM fact_order_items oi
JOIN dim_products dp ON dp.product_id = oi.product_id
GROUP BY dp.category_name
ORDER BY revenue_rank;


-- ============================================================================
-- QUERY 12 — PAGE 1/2 — Running (cumulative) revenue over time
-- Business question: What does cumulative revenue growth look like?
-- ============================================================================
WITH monthly AS (
    SELECT d.year, d.month, SUM(oi.price) AS monthly_revenue
    FROM fact_order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    JOIN dim_date d     ON d.date_key = fo.purchase_date
    GROUP BY d.year, d.month
)
SELECT
    year,
    month,
    ROUND(monthly_revenue::numeric, 2) AS monthly_revenue,
    ROUND(SUM(monthly_revenue) OVER (ORDER BY year, month)::numeric, 2) AS running_revenue
FROM monthly
ORDER BY year, month;


-- ============================================================================
-- QUERY 13 — PAGE 1/2 — Month-over-month growth %
-- Business question: How fast is revenue growing or shrinking month to month?
-- NOTE: 2016 only has a few months of data — MoM % for early months will
-- look extreme or nonsensical. Filter or footnote this when you chart it.
-- ============================================================================
WITH monthly AS (
    SELECT d.year, d.month, SUM(oi.price) AS monthly_revenue
    FROM fact_order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    JOIN dim_date d     ON d.date_key = fo.purchase_date
    GROUP BY d.year, d.month
)
SELECT
    year,
    month,
    ROUND(monthly_revenue::numeric, 2) AS monthly_revenue,
    ROUND(
        100.0 * (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY year, month))
        / NULLIF(LAG(monthly_revenue) OVER (ORDER BY year, month), 0)
    , 1) AS mom_growth_pct
FROM monthly
ORDER BY year, month;


-- ============================================================================
-- QUERY 14 — PAGE 3 — Top customers by revenue
-- Business question: Who are the highest-value customers?
-- ============================================================================
SELECT
    customer_unique_id,
    COUNT(*)                                    AS order_count,
    ROUND(SUM(total_payment_value)::numeric, 2) AS total_spent
FROM fact_orders
GROUP BY customer_unique_id
ORDER BY total_spent DESC
LIMIT 20;


-- ============================================================================
-- QUERY 15 — PAGE 4 — Seller ranking within state
-- Business question: Who's the top seller in each state?
-- ============================================================================
WITH seller_rev AS (
    SELECT ds.seller_id, ds.state, SUM(oi.price) AS revenue
    FROM fact_order_items oi
    JOIN dim_sellers ds ON ds.seller_id = oi.seller_id
    GROUP BY ds.seller_id, ds.state
)
SELECT
    seller_id,
    state,
    ROUND(revenue::numeric, 2) AS revenue,
    RANK() OVER (PARTITION BY state ORDER BY revenue DESC) AS rank_in_state
FROM seller_rev
ORDER BY state, rank_in_state;


-- ============================================================================
-- QUERY 16 — PAGE 4 — Late delivery analysis by customer state
-- Business question: Which regions have the worst late-delivery problem?
-- ============================================================================
SELECT
    dc.state,
    COUNT(*) FILTER (WHERE fo.order_status = 'delivered')  AS delivered_orders,
    COUNT(*) FILTER (WHERE fo.is_on_time = false)            AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE fo.is_on_time = false)
        / NULLIF(COUNT(*) FILTER (WHERE fo.order_status = 'delivered'), 0), 1) AS late_pct,
    ROUND(AVG(fo.delivery_delay_days) FILTER (WHERE fo.is_on_time = false)::numeric, 1) AS avg_days_late
FROM fact_orders fo
JOIN dim_customers dc ON dc.customer_unique_id = fo.customer_unique_id
GROUP BY dc.state
ORDER BY late_pct DESC;


-- ============================================================================
-- QUERY 17 — PAGE 3/4 — Review score vs. delivery delay
-- Business question: Does arriving late actually hurt customer satisfaction?
-- This is the query behind the Python statistical test (python/04_statistical_tests.py).
-- ============================================================================
SELECT
    CASE
        WHEN delivery_delay_days <= -7 THEN '1. Early (7+ days)'
        WHEN delivery_delay_days <= 0  THEN '2. On time / slightly early'
        WHEN delivery_delay_days <= 7  THEN '3. Late (1-7 days)'
        ELSE '4. Very late (7+ days)'
    END AS delivery_bucket,
    ROUND(AVG(review_score)::numeric, 2) AS avg_review_score,
    COUNT(*) AS order_count
FROM fact_orders
WHERE order_status = 'delivered'
GROUP BY 1
ORDER BY 1;


-- ============================================================================
-- QUERY 18 — PAGE 2/3 — Revenue concentration (Pareto by customer)
-- Business question: How much of total revenue comes from the top customers?
-- ============================================================================
WITH customer_revenue AS (
    SELECT customer_unique_id, SUM(total_payment_value) AS revenue
    FROM fact_orders
    GROUP BY customer_unique_id
),
ranked AS (
    SELECT
        customer_unique_id,
        revenue,
        NTILE(5) OVER (ORDER BY revenue DESC) AS revenue_quintile   -- quintile 1 = top 20% spenders
    FROM customer_revenue
)
SELECT
    revenue_quintile,
    COUNT(*)                                    AS customers,
    ROUND(SUM(revenue)::numeric, 2)             AS quintile_revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_total_revenue
FROM ranked
GROUP BY revenue_quintile
ORDER BY revenue_quintile;


-- ============================================================================
-- QUERY 19 — PAGE 3 — RFM customer segmentation
-- Business question: Who are the high-value, regular, and low-value customers?
-- Quintile scoring (not arbitrary dollar thresholds) on Recency and Monetary
-- value; segment = r_score + m_score (High 8-10, Regular 5-7, Low 2-4).
-- Frequency is deliberately NOT scored: ~97% of customers ordered exactly
-- once, so splitting that column into 5 groups only creates arbitrary,
-- row-order-dependent noise. Repeat buying is flagged separately instead.
-- Same logic as 03_customer_segments.sql.
-- ============================================================================
WITH customer_rfm AS (
    SELECT
        customer_unique_id,
        (SELECT MAX(purchase_date) FROM fact_orders) - MAX(purchase_date) AS recency_days,
        COUNT(*)                    AS frequency,
        SUM(total_payment_value)    AS monetary
    FROM fact_orders
    GROUP BY customer_unique_id
),
scored AS (
    SELECT
        customer_unique_id, recency_days, frequency, monetary,
        (6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_unique_id)) AS r_score,  -- most recent -> highest
        (6 - NTILE(5) OVER (ORDER BY monetary DESC,   customer_unique_id)) AS m_score   -- highest spend -> highest
    FROM customer_rfm
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary::numeric, 2) AS monetary,
    r_score, m_score,
    (r_score + m_score)  AS rfm_total,
    (frequency > 1)      AS is_repeat_customer,
    CASE
        WHEN r_score + m_score >= 8 THEN 'High Value'
        WHEN r_score + m_score >= 5 THEN 'Regular'
        ELSE 'Low Value'
    END AS customer_segment
FROM scored
ORDER BY rfm_total DESC;


-- ============================================================================
-- QUERY 20 — PAGE 3 — Potentially inactive (lapsed) customers
-- Business question: Which past repeat buyers have gone quiet?
-- NOTE: "today" doesn't exist in a historical dataset, so "inactive" is
-- defined relative to the dataset's own most recent order date. Restricted
-- to customers who ordered more than once — a one-time buyer going quiet
-- after their only order isn't a meaningful "lapsed" signal.
-- ============================================================================
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS order_count, MAX(purchase_date) AS last_order_date
    FROM fact_orders
    GROUP BY customer_unique_id
),
reference_date AS (
    SELECT MAX(purchase_date) AS max_date FROM fact_orders
)
SELECT
    co.customer_unique_id,
    co.order_count,
    co.last_order_date,
    r.max_date - co.last_order_date AS days_since_last_order
FROM customer_orders co
CROSS JOIN reference_date r
WHERE co.order_count > 1
  AND r.max_date - co.last_order_date > 180
ORDER BY days_since_last_order DESC;

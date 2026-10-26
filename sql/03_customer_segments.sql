-- ============================================================================
-- Customer segments (RFM-based), built as a table so it can be exported to
-- CSV and loaded into Power BI the same way as the star-schema tables.
-- Run once in pgAdmin's Query Tool. Safe to re-run (it drops and rebuilds).
--
-- METHOD
--   Recency  score (1-5): quintiles of days since the customer's last order
--   Monetary score (1-5): quintiles of total spend
--   Segment = Recency score + Monetary score  (range 2-10)
--       High Value : 8-10     Regular : 5-7     Low Value : 2-4
--
-- WHY FREQUENCY IS NOT IN THE SCORE
--   About 97% of customers in this dataset ordered exactly once. Splitting a
--   column where almost every value is identical into 5 equal groups (NTILE)
--   forces customers with identical behaviour into different groups, and
--   which group each one lands in depends on physical row order, so the
--   result can change between runs. It added arbitrary noise to the
--   segments instead of signal.
--   Repeat buying is reported separately as is_repeat_customer.
--
-- Column names and order match the previous version of this table, so the
-- Power BI table can simply be refreshed. f_score is kept for that reason
-- only (1 = single order, 5 = repeat) and is not used in rfm_total.
--
-- Tie-breaks on customer_unique_id make every run return identical results.
-- ============================================================================

DROP TABLE IF EXISTS customer_segments;

CREATE TABLE customer_segments AS
WITH customer_rfm AS (
    SELECT
        customer_unique_id,
        (SELECT MAX(purchase_date) FROM fact_orders) - MAX(purchase_date) AS recency_days,
        COUNT(*)                 AS frequency,
        SUM(total_payment_value) AS monetary
    FROM fact_orders
    GROUP BY customer_unique_id
),
scored AS (
    SELECT
        customer_unique_id, recency_days, frequency, monetary,
        (6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_unique_id)) AS r_score,
        (6 - NTILE(5) OVER (ORDER BY monetary DESC,   customer_unique_id)) AS m_score
    FROM customer_rfm
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary::numeric, 2) AS monetary,
    r_score,
    CASE WHEN frequency > 1 THEN 5 ELSE 1 END AS f_score,   -- informational only
    m_score,
    (r_score + m_score)         AS rfm_total,
    (frequency > 1)             AS is_repeat_customer,
    CASE
        WHEN r_score + m_score >= 8 THEN 'High Value'
        WHEN r_score + m_score >= 5 THEN 'Regular'
        ELSE 'Low Value'
    END AS customer_segment
FROM scored;

-- Quick check after running: the three segments should be roughly
-- 24% High Value / 52% Regular / 24% Low Value.
SELECT customer_segment,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM customer_segments
GROUP BY customer_segment
ORDER BY customer_segment;

-- ============================================================================
-- OLIST E-COMMERCE PROJECT — PHASE 1: DATA FOUNDATION
-- PostgreSQL. Loads the 9 raw CSVs, then builds the cleaned star schema:
--   dim_customers, dim_products, dim_sellers, dim_geolocation, dim_date
--   fact_orders, fact_order_items
--
-- Run this top to bottom in psql or your SQL client. It is safe to re-run —
-- every table is dropped and rebuilt from scratch.
-- ============================================================================


-- ============================================================================
-- SECTION 0: RAW STAGING TABLES
-- These mirror the 9 CSVs exactly (column names/typos preserved on purpose,
-- e.g. "product_name_lenght" is the real column name in the source file).
-- Update the file paths in the \copy commands to match your machine before
-- running this section. \copy is a psql client-side command — it reads local
-- files, so run this file with psql, not through a GUI "execute" button that
-- doesn't support \copy.
-- ============================================================================

DROP TABLE IF EXISTS raw_orders CASCADE;
CREATE TABLE raw_orders (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);

DROP TABLE IF EXISTS raw_order_items CASCADE;
CREATE TABLE raw_order_items (
    order_id             TEXT,
    order_item_id        INTEGER,
    product_id           TEXT,
    seller_id            TEXT,
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2),
    freight_value        NUMERIC(10,2)
);

DROP TABLE IF EXISTS raw_order_payments CASCADE;
CREATE TABLE raw_order_payments (
    order_id              TEXT,
    payment_sequential    INTEGER,
    payment_type          TEXT,
    payment_installments  INTEGER,
    payment_value         NUMERIC(10,2)
);

DROP TABLE IF EXISTS raw_order_reviews CASCADE;
CREATE TABLE raw_order_reviews (
    review_id                TEXT,
    order_id                 TEXT,
    review_score             INTEGER,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);

DROP TABLE IF EXISTS raw_customers CASCADE;
CREATE TABLE raw_customers (
    customer_id               TEXT,
    customer_unique_id        TEXT,
    customer_zip_code_prefix  INTEGER,
    customer_city             TEXT,
    customer_state            TEXT
);

DROP TABLE IF EXISTS raw_products CASCADE;
CREATE TABLE raw_products (
    product_id                  TEXT,
    product_category_name       TEXT,
    product_name_lenght         INTEGER,
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            INTEGER,
    product_length_cm           INTEGER,
    product_height_cm           INTEGER,
    product_width_cm            INTEGER
);

DROP TABLE IF EXISTS raw_sellers CASCADE;
CREATE TABLE raw_sellers (
    seller_id                TEXT,
    seller_zip_code_prefix   INTEGER,
    seller_city              TEXT,
    seller_state             TEXT
);

DROP TABLE IF EXISTS raw_category_translation CASCADE;
CREATE TABLE raw_category_translation (
    product_category_name           TEXT,
    product_category_name_english   TEXT
);

DROP TABLE IF EXISTS raw_geolocation CASCADE;
CREATE TABLE raw_geolocation (
    geolocation_zip_code_prefix  INTEGER,
    geolocation_lat              NUMERIC,
    geolocation_lng              NUMERIC,
    geolocation_city             TEXT,
    geolocation_state            TEXT
);

-- Load — edit these paths to point at your local CSVs
\copy raw_orders               FROM 'PATH/olist_orders_dataset.csv'                WITH (FORMAT csv, HEADER true);
\copy raw_order_items          FROM 'PATH/olist_order_items_dataset.csv'           WITH (FORMAT csv, HEADER true);
\copy raw_order_payments       FROM 'PATH/olist_order_payments_dataset.csv'        WITH (FORMAT csv, HEADER true);
\copy raw_order_reviews        FROM 'PATH/olist_order_reviews_dataset.csv'         WITH (FORMAT csv, HEADER true);
\copy raw_customers            FROM 'PATH/olist_customers_dataset.csv'             WITH (FORMAT csv, HEADER true);
\copy raw_products             FROM 'PATH/olist_products_dataset.csv'              WITH (FORMAT csv, HEADER true);
\copy raw_sellers              FROM 'PATH/olist_sellers_dataset.csv'               WITH (FORMAT csv, HEADER true);
\copy raw_category_translation FROM 'PATH/product_category_name_translation.csv'   WITH (FORMAT csv, HEADER true);
\copy raw_geolocation          FROM 'PATH/olist_geolocation_dataset.csv'           WITH (FORMAT csv, HEADER true);


-- ============================================================================
-- SECTION 1: DIM_DATE
-- Built, not loaded — one row per calendar day spanning the order history.
-- ============================================================================

DROP TABLE IF EXISTS dim_date CASCADE;
CREATE TABLE dim_date AS
SELECT
    d::date                                    AS date_key,
    EXTRACT(YEAR FROM d)::INT                  AS year,
    EXTRACT(MONTH FROM d)::INT                 AS month,
    TRIM(TO_CHAR(d, 'Month'))                  AS month_name,
    EXTRACT(QUARTER FROM d)::INT                AS quarter,
    'Q' || EXTRACT(QUARTER FROM d)::INT        AS quarter_label,
    EXTRACT(DOW FROM d)::INT                   AS day_of_week,      -- 0=Sunday
    TRIM(TO_CHAR(d, 'Day'))                    AS day_name,
    (EXTRACT(DOW FROM d) IN (0, 6))            AS is_weekend
FROM generate_series(
    (SELECT MIN(order_purchase_timestamp)::date FROM raw_orders),
    (SELECT MAX(order_purchase_timestamp)::date FROM raw_orders),
    interval '1 day'
) AS d;

ALTER TABLE dim_date ADD PRIMARY KEY (date_key);


-- ============================================================================
-- SECTION 2: DIM_GEOLOCATION
-- The raw file has ~1M rows for far fewer unique zip prefixes (multiple
-- lat/lng samples per zip). Collapse to one row per zip: average lat/lng,
-- and the most frequent city/state combo for that zip.
-- ============================================================================

DROP TABLE IF EXISTS dim_geolocation CASCADE;
CREATE TABLE dim_geolocation AS
WITH zip_lat_lng AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
        AVG(geolocation_lat) AS lat,
        AVG(geolocation_lng) AS lng
    FROM raw_geolocation
    GROUP BY geolocation_zip_code_prefix
),
zip_city_state_ranked AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
        geolocation_city AS city,
        geolocation_state AS state,
        ROW_NUMBER() OVER (
            PARTITION BY geolocation_zip_code_prefix
            ORDER BY COUNT(*) DESC
        ) AS rn
    FROM raw_geolocation
    GROUP BY geolocation_zip_code_prefix, geolocation_city, geolocation_state
)
SELECT
    ll.zip_code_prefix,
    ll.lat,
    ll.lng,
    cs.city,
    cs.state
FROM zip_lat_lng ll
JOIN zip_city_state_ranked cs
    ON ll.zip_code_prefix = cs.zip_code_prefix
   AND cs.rn = 1;

ALTER TABLE dim_geolocation ADD PRIMARY KEY (zip_code_prefix);


-- ============================================================================
-- SECTION 3: DIM_CUSTOMERS
-- customer_id in the raw file is generated per ORDER, not per person.
-- customer_unique_id is the real customer — this is the grain we dedupe to.
-- Without this step, every "customer" looks like a one-time buyer.
-- ============================================================================

DROP TABLE IF EXISTS dim_customers CASCADE;
CREATE TABLE dim_customers AS
SELECT DISTINCT ON (customer_unique_id)
    customer_unique_id,
    customer_zip_code_prefix AS zip_code_prefix,
    customer_city            AS city,
    customer_state           AS state
FROM raw_customers
ORDER BY customer_unique_id, customer_id;   -- deterministic pick if a person has multiple records

ALTER TABLE dim_customers ADD PRIMARY KEY (customer_unique_id);


-- ============================================================================
-- SECTION 4: DIM_PRODUCTS
-- Joins the English category name; falls back to the raw Portuguese name or
-- 'unknown' when a category has no match in the translation table.
-- ============================================================================

DROP TABLE IF EXISTS dim_products CASCADE;
CREATE TABLE dim_products AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_name,
    p.product_name_lenght        AS name_length,
    p.product_description_lenght AS description_length,
    p.product_photos_qty         AS photos_qty,
    p.product_weight_g           AS weight_g,
    p.product_length_cm          AS length_cm,
    p.product_height_cm          AS height_cm,
    p.product_width_cm           AS width_cm
FROM raw_products p
LEFT JOIN raw_category_translation t
    ON p.product_category_name = t.product_category_name;

ALTER TABLE dim_products ADD PRIMARY KEY (product_id);


-- ============================================================================
-- SECTION 5: DIM_SELLERS
-- ============================================================================

DROP TABLE IF EXISTS dim_sellers CASCADE;
CREATE TABLE dim_sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix AS zip_code_prefix,
    seller_city            AS city,
    seller_state            AS state
FROM raw_sellers;

ALTER TABLE dim_sellers ADD PRIMARY KEY (seller_id);


-- ============================================================================
-- SECTION 6: FACT_ORDERS (grain = one row per order)
-- Resolves customer_id -> customer_unique_id, aggregates payments to order
-- level (an order can have several payment rows), and takes the latest
-- review if an order somehow has more than one.
-- ============================================================================

DROP TABLE IF EXISTS fact_orders CASCADE;
CREATE TABLE fact_orders AS
WITH customer_bridge AS (
    SELECT customer_id, customer_unique_id
    FROM raw_customers
),
payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value)                                    AS total_payment_value,
        MAX(payment_installments)                             AS max_installments,
        COUNT(*)                                               AS payment_transaction_count,
        (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS primary_payment_type
    FROM raw_order_payments
    GROUP BY order_id
),
reviews_agg AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM raw_order_reviews
    ORDER BY order_id, review_answer_timestamp DESC
)
SELECT
    o.order_id,
    cb.customer_unique_id,
    o.order_status,
    o.order_purchase_timestamp::date AS purchase_date,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    -- Positive = delivered later than estimate, negative/zero = on time or early.
    -- NULL for anything not yet delivered — don't use these orders for delivery KPIs.
    CASE WHEN o.order_status = 'delivered'
         THEN (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date)
    END AS delivery_delay_days,
    CASE WHEN o.order_status = 'delivered'
         THEN (o.order_delivered_customer_date <= o.order_estimated_delivery_date)
    END AS is_on_time,
    CASE WHEN o.order_status = 'delivered'
         THEN EXTRACT(DAY FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
    END AS delivery_time_days,
    r.review_score,
    p.total_payment_value,
    p.max_installments,
    p.payment_transaction_count,
    p.primary_payment_type
FROM raw_orders o
LEFT JOIN customer_bridge cb ON o.customer_id = cb.customer_id
LEFT JOIN payments_agg p     ON o.order_id = p.order_id
LEFT JOIN reviews_agg r      ON o.order_id = r.order_id;

ALTER TABLE fact_orders ADD PRIMARY KEY (order_id);
ALTER TABLE fact_orders ADD CONSTRAINT fk_fo_customer
    FOREIGN KEY (customer_unique_id) REFERENCES dim_customers(customer_unique_id);
ALTER TABLE fact_orders ADD CONSTRAINT fk_fo_date
    FOREIGN KEY (purchase_date) REFERENCES dim_date(date_key);

CREATE INDEX idx_fact_orders_customer ON fact_orders(customer_unique_id);
CREATE INDEX idx_fact_orders_date     ON fact_orders(purchase_date);
CREATE INDEX idx_fact_orders_status   ON fact_orders(order_status);


-- ============================================================================
-- SECTION 7: FACT_ORDER_ITEMS (grain = one row per item within an order)
-- Keep this separate from fact_orders — orders can have multiple items from
-- multiple sellers, so item-level rows must never be merged into order-level
-- totals without aggregating first.
-- ============================================================================

DROP TABLE IF EXISTS fact_order_items CASCADE;
CREATE TABLE fact_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value,
    ROUND((oi.freight_value / NULLIF(oi.price, 0))::numeric, 4) AS freight_pct_of_price
FROM raw_order_items oi;

ALTER TABLE fact_order_items ADD PRIMARY KEY (order_id, order_item_id);
ALTER TABLE fact_order_items ADD CONSTRAINT fk_foi_order
    FOREIGN KEY (order_id) REFERENCES fact_orders(order_id);
ALTER TABLE fact_order_items ADD CONSTRAINT fk_foi_product
    FOREIGN KEY (product_id) REFERENCES dim_products(product_id);
ALTER TABLE fact_order_items ADD CONSTRAINT fk_foi_seller
    FOREIGN KEY (seller_id) REFERENCES dim_sellers(seller_id);

CREATE INDEX idx_foi_order   ON fact_order_items(order_id);
CREATE INDEX idx_foi_product ON fact_order_items(product_id);
CREATE INDEX idx_foi_seller  ON fact_order_items(seller_id);


-- ============================================================================
-- SECTION 8: SANITY CHECKS
-- Run these after the build to confirm the transformation did what it should.
-- ============================================================================

-- fact_order_items should have exactly as many rows as raw_order_items
-- (pure passthrough, no aggregation at this grain)
SELECT COUNT(*) AS raw_items, (SELECT COUNT(*) FROM fact_order_items) AS fact_items
FROM raw_order_items;

-- fact_orders should have exactly as many rows as raw_orders
-- (one row per order, payments/reviews aggregated in, not fanned out)
SELECT COUNT(*) AS raw_orders_count, (SELECT COUNT(*) FROM fact_orders) AS fact_orders_count
FROM raw_orders;

-- THE key check: this is the customer_id vs customer_unique_id gap.
-- order_level_ids will be close to the number of orders; real_customers
-- will be noticeably smaller — that gap is your repeat-customer base.
SELECT
    COUNT(DISTINCT customer_id)        AS order_level_ids,
    COUNT(DISTINCT customer_unique_id) AS real_customers
FROM raw_customers;

-- Any products that fell back to 'unknown' because their category wasn't
-- in the translation table (worth knowing about before you build category charts)
SELECT COUNT(*) FROM dim_products WHERE category_name = 'unknown';

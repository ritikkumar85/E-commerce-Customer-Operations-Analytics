# ============================================================================
# OLIST E-COMMERCE PROJECT — PHASE 3, STAGE 2: DATA PREPARATION
# Run in a new Colab cell (after Drive is mounted). Self-contained — it
# reloads the raw CSVs itself, so it doesn't depend on 01_data_audit.py still being
# in memory.
#
# Produces two dataframes used by everything from here on:
#   orders_clean  — one row per order, with real dates, delivery timing,
#                   review score, and order-level revenue attached.
#   items_clean   — one row per item, with English category name and
#                   seller state attached.
# ============================================================================

import pandas as pd

folder_path = '/content/drive/MyDrive/olist_project'  # change if your folder name differs

files = {
    'orders': 'olist_orders_dataset.csv',
    'order_items': 'olist_order_items_dataset.csv',
    'order_payments': 'olist_order_payments_dataset.csv',
    'order_reviews': 'olist_order_reviews_dataset.csv',
    'customers': 'olist_customers_dataset.csv',
    'products': 'olist_products_dataset.csv',
    'sellers': 'olist_sellers_dataset.csv',
    'category_translation': 'product_category_name_translation.csv',
    'geolocation': 'olist_geolocation_dataset.csv',
}
dfs = {name: pd.read_csv(f'{folder_path}/{filename}') for name, filename in files.items()}


# ---- 1. Convert the date columns from plain text to real dates -------------
date_cols = ['order_purchase_timestamp', 'order_approved_at',
             'order_delivered_carrier_date', 'order_delivered_customer_date',
             'order_estimated_delivery_date']

orders = dfs['orders'].copy()
for col in date_cols:
    orders[col] = pd.to_datetime(orders[col])


# ---- 2. Delivery timing metrics (mirrors the same logic from the SQL build,
#         now computed independently in Python) -----------------------------
orders['delivery_delay_days'] = (
    orders['order_delivered_customer_date'].dt.normalize()
    - orders['order_estimated_delivery_date'].dt.normalize()
).dt.days
orders['delivery_time_days'] = (
    orders['order_delivered_customer_date'] - orders['order_purchase_timestamp']
).dt.days
orders['is_on_time'] = (orders['delivery_delay_days'] <= 0).astype('boolean')

# these three only mean something for orders that actually arrived —
# blank them out for anything not marked 'delivered'
not_delivered = orders['order_status'] != 'delivered'
orders.loc[not_delivered, 'delivery_delay_days'] = None
orders.loc[not_delivered, 'delivery_time_days'] = None
orders.loc[not_delivered, 'is_on_time'] = pd.NA


# ---- 3. Attach the real customer, the latest review, and order revenue ----
customer_map = dfs['customers'][['customer_id', 'customer_unique_id', 'customer_state']]
orders = orders.merge(customer_map, on='customer_id', how='left')

reviews = (
    dfs['order_reviews']
    .sort_values('review_answer_timestamp')
    .drop_duplicates('order_id', keep='last')  # keep the latest if an order somehow has more than one
)
orders = orders.merge(reviews[['order_id', 'review_score']], on='order_id', how='left')

order_revenue = dfs['order_items'].groupby('order_id').agg(
    order_revenue=('price', 'sum'),
    order_freight=('freight_value', 'sum')
).reset_index()
orders = orders.merge(order_revenue, on='order_id', how='left')

orders_clean = orders
print(f"orders_clean ready: {orders_clean.shape[0]:,} rows, {orders_clean.shape[1]} columns")
orders_clean.head()


# ---- 4. Item-level table with English category name and seller state ------
category_map = dfs['category_translation'].set_index('product_category_name')['product_category_name_english']
products = dfs['products'].copy()
products['category_name'] = (
    products['product_category_name']
    .map(category_map)                       # try the English translation first
    .fillna(products['product_category_name'])  # fall back to the raw Portuguese name
    .fillna('unknown')                        # fall back to 'unknown' if there's no category at all
)

items_clean = dfs['order_items'].merge(products[['product_id', 'category_name']], on='product_id', how='left')
items_clean = items_clean.merge(dfs['sellers'][['seller_id', 'seller_state']], on='seller_id', how='left')

print(f"items_clean ready: {items_clean.shape[0]:,} rows, {items_clean.shape[1]} columns")
items_clean.head()

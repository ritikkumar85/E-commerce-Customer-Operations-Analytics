# ============================================================================
# OLIST E-COMMERCE PROJECT — PHASE 3, STAGE 3: EXPLORATORY DATA ANALYSIS
# Run in a new Colab cell. Needs orders_clean and items_clean from 02_data_preparation.py
# to already exist in this session.
# ============================================================================

import matplotlib.pyplot as plt

# ---- A. Order revenue distribution -----------------------------------------
# Clipped at the 99th percentile — a handful of very large orders would
# otherwise squash the whole chart into one tall bar near zero.
p99 = orders_clean['order_revenue'].quantile(0.99)
plt.figure(figsize=(8, 4))
plt.hist(orders_clean['order_revenue'].dropna(), bins=50, range=(0, p99))
plt.title('Distribution of Order Revenue (up to the 99th percentile)')
plt.xlabel('Order Revenue (R$)')
plt.ylabel('Number of Orders')
plt.show()
print(f"Note: the priciest 1% of orders are all worth more than R$ {p99:,.2f} "
      f"and were left out of this chart so the main shape is readable.")


# ---- B. Monthly order volume ------------------------------------------------
monthly_orders = orders_clean.groupby(orders_clean['order_purchase_timestamp'].dt.to_period('M')).size()
plt.figure(figsize=(10, 4))
monthly_orders.plot(kind='line', marker='o')
plt.title('Orders per Month')
plt.xlabel('Month')
plt.ylabel('Number of Orders')
plt.xticks(rotation=45)
plt.tight_layout()
plt.show()


# ---- C. Delivery time distribution (delivered orders only) -----------------
plt.figure(figsize=(8, 4))
plt.hist(orders_clean['delivery_time_days'].dropna(), bins=40)
plt.title('Delivery Time Distribution (Purchase to Delivery, in Days)')
plt.xlabel('Days')
plt.ylabel('Number of Orders')
plt.show()


# ---- D. Freight cost as a % of item price -----------------------------------
priced_items = items_clean.loc[items_clean['price'] > 0, ['price', 'freight_value']].copy()
priced_items['freight_pct'] = priced_items['freight_value'] / priced_items['price'] * 100
plt.figure(figsize=(8, 4))
plt.hist(priced_items['freight_pct'].clip(upper=100), bins=40)
plt.title('Freight Cost as a % of Item Price')
plt.xlabel('Freight as % of Price (capped at 100%)')
plt.ylabel('Number of Items')
plt.show()


# ---- E. Review score distribution -------------------------------------------
plt.figure(figsize=(6, 4))
orders_clean['review_score'].value_counts().sort_index().plot(kind='bar')
plt.title('Review Score Distribution')
plt.xlabel('Review Score')
plt.ylabel('Number of Orders')
plt.show()


# ---- F. Orders per customer (repeat-purchase behavior) ----------------------
# Log scale on purpose — expect one huge bar at "1" and tiny slivers after
# it, since most customers in this dataset ordered exactly once.
orders_per_customer = orders_clean.groupby('customer_unique_id').size()
plt.figure(figsize=(6, 4))
orders_per_customer.value_counts().sort_index().plot(kind='bar', logy=True)
plt.title('Orders per Customer (log scale)')
plt.xlabel('Number of Orders')
plt.ylabel('Number of Customers (log scale)')
plt.show()

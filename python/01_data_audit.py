# ============================================================================
# OLIST E-COMMERCE PROJECT — PHASE 3, STAGE 1: DATA QUALITY AUDIT
# Run in Google Colab, in the cell AFTER you've mounted your Google Drive.
#
# This checks the RAW CSVs directly (not the cleaned Postgres tables) —
# the point of this stage is to independently verify data quality using
# pandas, as a separate check from what SQL already found.
# ============================================================================

import pandas as pd

folder_path = '/content/drive/MyDrive/olist_project'  # change this if you named your Drive folder differently

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

dfs = {}
for name, filename in files.items():
    dfs[name] = pd.read_csv(f'{folder_path}/{filename}')

print("All 9 files loaded. Row counts:")
for name, df in dfs.items():
    print(f"  {name:22s} {len(df):>9,} rows   {df.shape[1]} columns")


# ----------------------------------------------------------------------------
# For every table: missing values, duplicate rows, and column types.
# A column showing as text/string (often labeled 'object', sometimes 'str'
# depending on your pandas version) when it should be a date is expected
# right now — pandas doesn't know it's a date until we tell it to convert it,
# which happens in 02_data_preparation.py, not here.
# ----------------------------------------------------------------------------
for name, df in dfs.items():
    print(f"\n{'='*60}\n{name.upper()}\n{'='*60}")
    print(f"Shape: {df.shape[0]:,} rows x {df.shape[1]} columns\n")

    print("Missing values per column:")
    missing = df.isnull().sum()
    missing = missing[missing > 0]
    if missing.empty:
        print("  (none)")
    else:
        for col, count in missing.items():
            pct = 100 * count / len(df)
            print(f"  {col:30s} {count:>8,} missing  ({pct:.1f}%)")

    dup_count = df.duplicated().sum()
    print(f"\nFully duplicate rows: {dup_count:,}")

    print("\nColumn data types:")
    print(df.dtypes.to_string())


# ----------------------------------------------------------------------------
# TARGETED CHECKS — the specific issues this dataset is known for.
# These reproduce a couple of things the SQL queries already found, using
# pandas instead — a second, independent way of catching the same issues.
# ----------------------------------------------------------------------------

# 1) customer_id (per order) vs customer_unique_id (per real person)
c = dfs['customers']
print("\nCustomer ID check:")
print(f"  order-level customer_id:     {c['customer_id'].nunique():,}")
print(f"  real people (unique_id):     {c['customer_unique_id'].nunique():,}")

# 2) Confirm the order date columns are currently loaded as plain text
o = dfs['orders']
date_cols = ['order_purchase_timestamp', 'order_approved_at',
             'order_delivered_carrier_date', 'order_delivered_customer_date',
             'order_estimated_delivery_date']
print("\nOrder date columns - current type (text/string, not a real date yet):")
print(o[date_cols].dtypes)

# 3) Product categories with no English translation
p = dfs['products']
t = dfs['category_translation']
missing_categories = set(p['product_category_name'].dropna().unique()) - set(t['product_category_name'].unique())
print(f"\nProduct categories with no English translation: {len(missing_categories)}")
if missing_categories:
    print(missing_categories)

# 4) Products missing a category entirely
print(f"\nProducts with no category at all: {p['product_category_name'].isnull().sum():,}")

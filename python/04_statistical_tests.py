# ============================================================================
# OLIST E-COMMERCE PROJECT — PHASE 3, STAGE 4: STATISTICAL TEST
# Run in a new Colab cell. Needs orders_clean from 02_data_preparation.py to already exist
# in this session (re-run 02_data_preparation.py first if you get a NameError).
#
# Question: does a later delivery go along with a lower review score, more
# than you'd expect from random chance alone?
# ============================================================================

from scipy import stats

# Only orders that were actually delivered have both a real delay and a
# review to compare — anything else is dropped for this test.
test_data = orders_clean.dropna(subset=['delivery_delay_days', 'review_score']).copy()
print(f"Testing on {len(test_data):,} delivered, reviewed orders.")


# ---- Test 1: Spearman correlation ------------------------------------------
rho, p_value = stats.spearmanr(test_data['delivery_delay_days'], test_data['review_score'])
print(f"\nSpearman correlation: rho = {rho:.3f}, p-value = {p_value:.6f}")


# ---- Test 2: Kruskal-Wallis across delay buckets ---------------------------
# Same four buckets as SQL Query 17, so the two results are directly comparable.
def bucket(delay):
    if delay <= -7:
        return '1_early_7plus'
    elif delay <= 0:
        return '2_on_time'
    elif delay <= 7:
        return '3_late_1_7'
    else:
        return '4_very_late_7plus'

test_data['delay_bucket'] = test_data['delivery_delay_days'].apply(bucket)

groups = [group['review_score'].values for _, group in test_data.groupby('delay_bucket')]
h_stat, kw_p_value = stats.kruskal(*groups)
print(f"Kruskal-Wallis: H = {h_stat:.2f}, p-value = {kw_p_value:.6f}")

print("\nAverage review score by delay bucket (for context):")
print(test_data.groupby('delay_bucket')['review_score'].agg(['mean', 'count']).sort_index())

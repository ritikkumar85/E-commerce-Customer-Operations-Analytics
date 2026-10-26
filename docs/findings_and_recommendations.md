# E-Commerce Customer & Operations Intelligence
### Findings & Recommendations — Olist Brazilian E-Commerce Dataset (~100K orders, 2016–2018)

## Overview

This project analyzes order, customer, product, seller, and review data from a Brazilian
e-commerce marketplace to answer three management-level questions: what's driving sales
performance, who the valuable customers are, and how delivery/operations performance is
affecting the customer experience.

**Tools & approach:**
- **PostgreSQL** — a 7-table star schema built from 9 raw source files, including fixes for
  real data-quality issues (customer ID deduplication, geolocation normalization, missing
  category translations)
- **SQL** — 21 business-question-driven queries, including window functions, RFM scoring,
  and revenue-concentration analysis
- **Python** (Pandas, Matplotlib, SciPy) — independent data quality audit, exploratory
  analysis, and non-parametric statistical tests of delivery performance vs. satisfaction
- **Power BI** — a 4-page interactive dashboard (Executive Overview, Sales & Product,
  Customer Analytics, Operations) built on 12 DAX measures

**Headline numbers:** R$13.59M total revenue across 99K orders and 96K unique customers;
R$136.68 average order value; 4.09 average review score (out of 5); 93.23% of delivered
orders arriving on or before their estimated date.

---

## Key Findings

### 1. Late delivery is associated with sharply lower customer satisfaction
Across 95,824 delivered orders that received a review, average review score falls as delivery
gets later:

| Delivery outcome | Avg. review score |
|---|---|
| Early (7+ days) | 4.31 |
| On time | 4.17 |
| Late (1–7 days) | 2.71 |
| Very late (7+ days) | 1.70 |

93.23% of delivered orders arrive on or before their estimated date, so the business performs
well overall — but the roughly 7% that arrive late account for nearly all of the satisfaction
damage. In the tested sample, about 79% of orders arrived 7+ days early and 14% roughly on
time, versus 6.7% late (6,381 of 95,824). The drop is a cliff at the estimated date, not a
gradual slope: moving from a week early to on time costs about 0.15 points, moving from on
time to late costs about 1.45, and being more than a week late costs about 2.5.

These bucket averages were computed independently in Power BI and in Python and match
exactly. Statistical tests (Python, SciPy):

- **Kruskal-Wallis** across the four delivery buckets: H = 9,990, p < 0.001. Review-score
  distributions differ significantly between buckets. As a rough effect size, H / (n - 1) is
  about 0.10, meaning roughly a tenth of the variation in score ranks is tied to the
  delivery bucket.
- **Spearman rank correlation** between days late (vs. the estimate) and review score:
  rho = -0.18, p < 0.001. Modest overall because about 93% of orders sit in the flat region
  where timing barely matters; the relationship is concentrated in late orders rather than
  spread evenly.

Separately, 79% of tested orders arrived a week or more before the promised date, which
suggests the estimated delivery dates are conservative (average actual delivery is about
12 days).

### 2. Repeat purchases are rare — most revenue comes from first-time buyers
Only **3.12%** of customers placed more than one order in this dataset. The overwhelming
majority of revenue is driven by single-order transactions rather than loyalty or repeat
purchasing behavior.

### 3. Revenue and customer base are heavily concentrated in São Paulo
São Paulo (SP) leads every other state by a wide margin in both customer count and revenue,
consistent with its outsized role in the Brazilian e-commerce market. Revenue drops off
sharply moving down the state ranking (RJ, MG, RS, PR, and smaller states contributing much
less), meaning logistics and marketing investment concentrated in SP carries the most leverage.

### 4. Freight cost burden varies significantly by product category
Freight as a percentage of item price averages 16.57% across the business but varies widely
by category: home_comfort_2 (53.97%), flowers (44.04%) and furniture_mattress_and_upholstery
(37.33%) sit far above the average. Categories differ greatly in order volume, so the
highest percentages should be read as indicative rather than conclusive unless the category
also has substantial sales.

### 5. Customers are segmented into three value tiers using Recency and Monetary scores
Each customer receives a Recency score and a Monetary score from 1 to 5 (quintiles of days
since last order and of total spend). The two are summed, giving High Value (8-10),
Regular (5-7) and Low Value (2-4) tiers. Repeat buying is tracked separately as its own flag.

Methodology note: Frequency is deliberately left out of the score. Because ~97% of customers
ordered exactly once (see Finding 2), frequency does not distinguish customers, and splitting
it into five equal groups forces identical customers into different groups arbitrarily.
Two earlier versions of this segmentation were rejected for exactly that reason: one labelled
large one-time spenders as "One-Time" buyers regardless of spend, and one included a
frequency score that added arbitrary, row-order-dependent noise to the tiers.

---

## Recommendations

| Finding | Recommendation |
|---|---|
| Late delivery sharply lowers satisfaction (Finding 1) | Prioritize logistics and seller delivery-performance monitoring specifically for shipments at risk of running late — the group causing the most damage is also the smallest, making it a high-leverage place to intervene. |
| Repeat purchases are rare (Finding 2) | Given low reorder rates, invest in maximizing satisfaction and order value on the first purchase (fast, reliable delivery; responsive support) rather than loyalty-program-style repeat incentives that assume a second order will happen. |
| Revenue is SP-concentrated (Finding 3) | Continue prioritizing fulfillment infrastructure and seller density in São Paulo and other top-revenue states, while piloting targeted demand-generation in lower-penetration states to test for untapped growth. |
| Freight burden varies by category (Finding 4) | Review freight pricing, packaging, or free-shipping thresholds for the high-freight-percentage categories that also have meaningful order volume, to protect margins on those product lines. |
| High Value segment identified (Finding 5) | Target the High Value segment with retention-focused offers: these customers combine recent purchases with high spend, even though almost none are habitual repeat buyers. |

---

## Limitations

- The delivery-satisfaction result is an association, not proof of cause. Late orders may
  differ in other ways (remote states, particular sellers or categories) that also affect
  review scores, and the tests do not control for those. The tests also cover only delivered
  orders that received a review (95,824 of 99,441 orders); orders that never arrived, which
  averaged a 1.75 review score in the dashboard, fall outside them.
- The segmentation uses only Recency and Monetary value, so it cannot separate customers
  by how often they buy; with ~97% single-order customers, there is little frequency
  information to use. The tier cut-offs (8 and 5 on a 2-10 scale) are a reasonable but
  judgement-based choice.

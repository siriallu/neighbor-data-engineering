# Neighbor Data Engineer Take-Home — Submission

**Candidate:** Sireesha A
**Date:** 06-25-2026

---

## Setup (under 5 minutes)

**Prerequisites:** Python 3.8+

**Step 1 — Create data folder shortcut inside solution/**
```bash
cd solution
cmd /c mklink /J data ..\data
```

**Step 2 — Install dependency**
```bash
pip install duckdb==1.5.4
```

**Step 3 — Run the pipeline**
```bash
python setup.py
```

Results are written to `solution/output/`:
- `output/ltv_cac_daily.csv`
- `output/ltv_cac_weekly.csv`
- `output/ltv_cac_monthly.csv`
- `output/ltv_cac_yearly.csv`

The script is idempotent — safe to run multiple times. All tables are `CREATE OR REPLACE`.

---

## Data Model

Three staging views read CSVs in-place (no copy). Three normalized tables build on top:

```
stg_users ──────────► dim_users ──────────────────────────────┐
                                                               ▼
stg_listings ──────── fct_listing_ltv ──────► fct_ltv_cac_{daily,weekly,monthly,yearly}
stg_predictions ────┘                                          ▲
stg_ad_spend ──────── fct_ad_spend_daily ─────────────────────┘
```

- **`dim_users`** — one row per user: user_id, join_date, acquisition_channel, state. Derived from the first snapshot (`snapshot_date = join_date`), which carries immutable fields.
- **`fct_listing_ltv`** — one row per listing with an ML prediction: listing_id, host_user_id, listed_date, host_ltv. INNER JOIN to predictions excludes listings with no prediction (they contribute $0 LTV).
- **`fct_ad_spend_daily`** — one row per (date, channel): total_spend collapsed across all campaigns.

---

## Modeling Choices and Rationale

**Sparse-snapshot de-duplication:** I use `WHERE snapshot_date = join_date` to get each user's first row. This is simpler than a window function and correct because both `join_date` and `acquisition_channel` are stated as immutable in the data dictionary.

**LTV attribution to join_date cohort:** All listings owned by a host are summed and attributed to that host's `join_date`, regardless of when the listings were created. The spec explicitly states cohort membership is by join date.

**No proration of ad spend:** CAC for a cohort = total ad spend on the users' join date for their channel. `attributed_signups` is explicitly described as noisy in the data dictionary — it comes from upstream marketing platforms and does not reliably count actual signups. Using raw spend totals per (date, channel) is the sound choice.

**CAC DISTINCT sub-select:** The CAC CTE uses `SELECT DISTINCT join_date, acquisition_channel FROM dim_users` before joining to `fct_ad_spend_daily`. This makes the business rule explicit — we collect the unique (day, channel) pairs that matter for this cohort — and protects against any future duplicate rows in dim_users inflating spend.

**Materialized reporting tables over views:** Pre-computed tables are instantaneous to read and signal production-oriented thinking (in real warehouses you would not re-run expensive joins on every BI tool refresh).

---

## Acquisition Cost Attribution

For each cohort, I identify the distinct `(join_date, acquisition_channel)` pairs where `acquisition_channel` is a paid channel (google_search, google_display, facebook, instagram, tiktok). I then sum all spend from `fct_ad_spend_daily` where `date = join_date AND channel = acquisition_channel`.

- `referral` and `organic` users → `acquisition_channel` set to NULL in `dim_users` → excluded from CAC CTE → $0 CAC
- Empty / unattributed users → also normalized to NULL → $0 CAC
- `ltv_cac_ratio` uses `NULLIF(total_cac, 0)` → returns NULL (not division-by-zero) for cohorts where all users are organic/referral

---

## Assumptions

1. `join_date` and `acquisition_channel` are immutable per the data dictionary.
2. One ML prediction per listing in this dataset — INNER JOIN to `listing_predictions` is safe.
3. Listings with no matching prediction contribute $0 LTV (excluded by INNER JOIN).
4. UTC is the implicit timezone; no conversion applied.
5. `reservations.csv` was not used. LTV is the host-side ML-predicted revenue, not realized renter payments.
6. Weekly grain uses Monday as the ISO week start (DuckDB default for `DATE_TRUNC('week', ...)`).
7. Days with paid-channel ad spend but no users joining on that channel still appear in `fct_ad_spend_daily` but are simply not joined to any cohort — they are correctly ignored.

---

## Tools Used

- **DuckDB 1.x** — zero-install OLAP engine; reads CSVs natively; full SQL with `DATE_TRUNC`, `DISTINCT ON`, window functions, and `COPY TO`. Ideal for a self-contained take-home: one `pip install`, no server, cross-platform.
- **Python 3.x** — orchestration only; no pandas or NumPy required.
- **Claude AI (claude-sonnet-4-6)** — used for SQL review and README drafting.
## AI Prompts Used

1. "In DuckDB, what is the most efficient way to deduplicate a sparse snapshot table 
and extract the first record per entity? The table emits rows only on change events, 
and I need the earliest snapshot per user_id to get immutable fields like join_date 
and acquisition_channel. Should I use DISTINCT ON, ROW_NUMBER, or MIN with GROUP BY?"

2. "I need to compute CAC (Customer Acquisition Cost) by user cohort using daily ad 
spend data. The ad platform's attributed_signups column is unreliable due to 
cross-device attribution noise. What is the correct SQL pattern to allocate total 
daily channel spend to cohorts based on join_date and acquisition_channel, without 
prorating by signup count?"

3. "For a cohort LTV:CAC analysis at multiple time grains (daily, weekly, monthly, 
yearly) in DuckDB, should I use DATE_TRUNC or YEARWEEK/EXTRACT for grain-level 
grouping? Also what is the correct way to handle NULL CAC (organic/referral users 
with zero acquisition cost) in the final ratio to avoid division by zero?"
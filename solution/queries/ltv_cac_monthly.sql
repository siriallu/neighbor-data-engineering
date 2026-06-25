-- ltv_cac_monthly.sql
-- LTV:CAC by join-month cohort (cohort_period = first day of month)
-- Run after setup.py has built the reporting tables.

SELECT
    cohort_period           AS month_start,
    user_count,
    host_count,
    listing_count,
    ROUND(total_ltv,      2) AS total_ltv,
    ROUND(total_cac,      2) AS total_cac,
    ROUND(ltv_cac_ratio,  4) AS ltv_cac_ratio
FROM fct_ltv_cac_monthly
ORDER BY cohort_period;

-- ltv_cac_yearly.sql
-- LTV:CAC by join-year cohort
-- Run after setup.py has built the reporting tables.

SELECT
    YEAR(cohort_period)     AS join_year,
    user_count,
    host_count,
    listing_count,
    ROUND(total_ltv,      2) AS total_ltv,
    ROUND(total_cac,      2) AS total_cac,
    ROUND(ltv_cac_ratio,  4) AS ltv_cac_ratio
FROM fct_ltv_cac_yearly
ORDER BY cohort_period;

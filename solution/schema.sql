-- ============================================================
-- schema.sql -- Neighbor LTV:CAC Data Model
-- Engine: DuckDB (in-memory, executed via setup.py)
-- ============================================================

-- -------------------------------------------------------
-- STAGING VIEWS -- read CSVs in-place, no data copied
-- -------------------------------------------------------

CREATE OR REPLACE VIEW stg_users AS
SELECT
    user_id,
    CAST(join_date     AS DATE)      AS join_date,
    state,
    status,
    NULLIF(TRIM(acquisition_channel), '') AS acquisition_channel,
    CAST(snapshot_date AS DATE)      AS snapshot_date
FROM read_csv_auto('data/users_daily_snapshot.csv', header=true);

CREATE OR REPLACE VIEW stg_listings AS
SELECT
    listing_id,
    host_user_id,
    status,
    city,
    state,
    CAST(monthly_price AS DECIMAL(12,2)) AS monthly_price,
    CAST(listed_date   AS DATE)          AS listed_date,
    CAST(snapshot_date AS DATE)          AS snapshot_date
FROM read_csv_auto('data/listings_daily_snapshot.csv', header=true);

CREATE OR REPLACE VIEW stg_predictions AS
SELECT
    prediction_id,
    listing_id,
    CAST(host_ltv    AS DECIMAL(14,2)) AS host_ltv,
    model_version,
    CAST(predicted_at AS TIMESTAMP)    AS predicted_at
FROM read_csv_auto('data/listing_predictions.csv', header=true);

CREATE OR REPLACE VIEW stg_ad_spend AS
SELECT
    CAST(date         AS DATE)         AS date,
    campaign_id,
    channel,
    CAST(spend_amount AS DECIMAL(12,2)) AS spend_amount,
    CAST(impressions  AS INTEGER)       AS impressions,
    CAST(attributed_signups AS INTEGER) AS attributed_signups
FROM read_csv_auto('data/ad_spend_daily.csv', header=true);

-- -------------------------------------------------------
-- DIM_USERS
-- One row per user from their first-ever snapshot row
-- (snapshot_date = join_date carries immutable fields).
-- referral/organic/null channel -> NULL ($0 CAC users).
-- -------------------------------------------------------

CREATE OR REPLACE TABLE dim_users AS
SELECT DISTINCT ON (user_id)
    user_id,
    join_date,
    CASE
        WHEN acquisition_channel IN ('referral', 'organic') THEN NULL
        ELSE acquisition_channel
    END AS acquisition_channel,
    state
FROM stg_users
WHERE snapshot_date = join_date
ORDER BY user_id, snapshot_date;

-- -------------------------------------------------------
-- FCT_LISTING_LTV
-- One row per listing that has an ML prediction.
-- LTV is attributed to host user (joined to dim_users at
-- query time by user_id = host_user_id -> join_date).
-- Listings without a prediction are excluded (contribute $0).
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_listing_ltv AS
WITH first_listing AS (
    SELECT DISTINCT ON (listing_id)
        listing_id,
        host_user_id,
        listed_date,
        city,
        state
    FROM stg_listings
    ORDER BY listing_id, snapshot_date
)
SELECT
    f.listing_id,
    f.host_user_id,
    f.listed_date,
    f.city,
    f.state,
    p.host_ltv,
    p.model_version
FROM first_listing f
INNER JOIN stg_predictions p ON p.listing_id = f.listing_id;

-- -------------------------------------------------------
-- FCT_AD_SPEND_DAILY
-- One row per (date, channel): total spend across all
-- campaigns. attributed_signups intentionally excluded --
-- it is noisy per spec and not used for proration.
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_ad_spend_daily AS
SELECT
    date,
    channel,
    SUM(spend_amount)  AS total_spend,
    SUM(impressions)   AS total_impressions
FROM stg_ad_spend
GROUP BY date, channel;

-- ============================================================
-- REPORTING TABLES (4 grains)
-- Pattern per grain:
--   cohort_ltv CTE  : sum LTV via dim_users -> fct_listing_ltv
--   cohort_cac CTE  : sum spend via DISTINCT (join_date, channel)
--                     sub-select -> fct_ad_spend_daily
--   Final SELECT    : join LTV + CAC, compute ratio
-- ============================================================

-- -------------------------------------------------------
-- FCT_LTV_CAC_DAILY  (grain: join_date)
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_ltv_cac_daily AS
WITH cohort_ltv AS (
    SELECT
        u.join_date                                              AS cohort_period,
        COUNT(DISTINCT u.user_id)                               AS user_count,
        COUNT(DISTINCT l.listing_id)                            AS listing_count,
        COUNT(DISTINCT CASE WHEN l.listing_id IS NOT NULL
                            THEN u.user_id END)                 AS host_count,
        COALESCE(SUM(l.host_ltv), 0)                           AS total_ltv
    FROM dim_users u
    LEFT JOIN fct_listing_ltv l ON l.host_user_id = u.user_id
    GROUP BY u.join_date
),
cohort_cac AS (
    SELECT
        u.join_date,
        COALESCE(SUM(s.total_spend), 0)                        AS total_cac
    FROM (
        SELECT DISTINCT join_date, acquisition_channel
        FROM dim_users
        WHERE acquisition_channel IS NOT NULL
    ) u
    LEFT JOIN fct_ad_spend_daily s
        ON s.date = u.join_date AND s.channel = u.acquisition_channel
    GROUP BY u.join_date
)
SELECT
    cl.cohort_period,
    cl.user_count,
    cl.host_count,
    cl.listing_count,
    cl.total_ltv,
    COALESCE(cc.total_cac, 0)                                  AS total_cac,
    cl.total_ltv / NULLIF(COALESCE(cc.total_cac, 0), 0)       AS ltv_cac_ratio
FROM cohort_ltv cl
LEFT JOIN cohort_cac cc ON cc.join_date = cl.cohort_period
ORDER BY cl.cohort_period;

-- -------------------------------------------------------
-- FCT_LTV_CAC_WEEKLY  (grain: ISO week, Monday anchor)
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_ltv_cac_weekly AS
WITH cohort_ltv AS (
    SELECT
        DATE_TRUNC('week', u.join_date)::DATE                  AS cohort_period,
        COUNT(DISTINCT u.user_id)                               AS user_count,
        COUNT(DISTINCT l.listing_id)                            AS listing_count,
        COUNT(DISTINCT CASE WHEN l.listing_id IS NOT NULL
                            THEN u.user_id END)                 AS host_count,
        COALESCE(SUM(l.host_ltv), 0)                           AS total_ltv
    FROM dim_users u
    LEFT JOIN fct_listing_ltv l ON l.host_user_id = u.user_id
    GROUP BY DATE_TRUNC('week', u.join_date)
),
cohort_cac AS (
    SELECT
        DATE_TRUNC('week', u.join_date)::DATE                  AS cohort_week,
        COALESCE(SUM(s.total_spend), 0)                        AS total_cac
    FROM (
        SELECT DISTINCT join_date, acquisition_channel
        FROM dim_users
        WHERE acquisition_channel IS NOT NULL
    ) u
    LEFT JOIN fct_ad_spend_daily s
        ON s.date = u.join_date AND s.channel = u.acquisition_channel
    GROUP BY DATE_TRUNC('week', u.join_date)
)
SELECT
    cl.cohort_period,
    cl.user_count,
    cl.host_count,
    cl.listing_count,
    cl.total_ltv,
    COALESCE(cc.total_cac, 0)                                  AS total_cac,
    cl.total_ltv / NULLIF(COALESCE(cc.total_cac, 0), 0)       AS ltv_cac_ratio
FROM cohort_ltv cl
LEFT JOIN cohort_cac cc ON cc.cohort_week = cl.cohort_period
ORDER BY cl.cohort_period;

-- -------------------------------------------------------
-- FCT_LTV_CAC_MONTHLY  (grain: first day of join month)
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_ltv_cac_monthly AS
WITH cohort_ltv AS (
    SELECT
        DATE_TRUNC('month', u.join_date)::DATE                 AS cohort_period,
        COUNT(DISTINCT u.user_id)                               AS user_count,
        COUNT(DISTINCT l.listing_id)                            AS listing_count,
        COUNT(DISTINCT CASE WHEN l.listing_id IS NOT NULL
                            THEN u.user_id END)                 AS host_count,
        COALESCE(SUM(l.host_ltv), 0)                           AS total_ltv
    FROM dim_users u
    LEFT JOIN fct_listing_ltv l ON l.host_user_id = u.user_id
    GROUP BY DATE_TRUNC('month', u.join_date)
),
cohort_cac AS (
    SELECT
        DATE_TRUNC('month', u.join_date)::DATE                 AS cohort_month,
        COALESCE(SUM(s.total_spend), 0)                        AS total_cac
    FROM (
        SELECT DISTINCT join_date, acquisition_channel
        FROM dim_users
        WHERE acquisition_channel IS NOT NULL
    ) u
    LEFT JOIN fct_ad_spend_daily s
        ON s.date = u.join_date AND s.channel = u.acquisition_channel
    GROUP BY DATE_TRUNC('month', u.join_date)
)
SELECT
    cl.cohort_period,
    cl.user_count,
    cl.host_count,
    cl.listing_count,
    cl.total_ltv,
    COALESCE(cc.total_cac, 0)                                  AS total_cac,
    cl.total_ltv / NULLIF(COALESCE(cc.total_cac, 0), 0)       AS ltv_cac_ratio
FROM cohort_ltv cl
LEFT JOIN cohort_cac cc ON cc.cohort_month = cl.cohort_period
ORDER BY cl.cohort_period;

-- -------------------------------------------------------
-- FCT_LTV_CAC_YEARLY  (grain: first day of join year)
-- -------------------------------------------------------

CREATE OR REPLACE TABLE fct_ltv_cac_yearly AS
WITH cohort_ltv AS (
    SELECT
        DATE_TRUNC('year', u.join_date)::DATE                  AS cohort_period,
        COUNT(DISTINCT u.user_id)                               AS user_count,
        COUNT(DISTINCT l.listing_id)                            AS listing_count,
        COUNT(DISTINCT CASE WHEN l.listing_id IS NOT NULL
                            THEN u.user_id END)                 AS host_count,
        COALESCE(SUM(l.host_ltv), 0)                           AS total_ltv
    FROM dim_users u
    LEFT JOIN fct_listing_ltv l ON l.host_user_id = u.user_id
    GROUP BY DATE_TRUNC('year', u.join_date)
),
cohort_cac AS (
    SELECT
        DATE_TRUNC('year', u.join_date)::DATE                  AS cohort_year,
        COALESCE(SUM(s.total_spend), 0)                        AS total_cac
    FROM (
        SELECT DISTINCT join_date, acquisition_channel
        FROM dim_users
        WHERE acquisition_channel IS NOT NULL
    ) u
    LEFT JOIN fct_ad_spend_daily s
        ON s.date = u.join_date AND s.channel = u.acquisition_channel
    GROUP BY DATE_TRUNC('year', u.join_date)
)
SELECT
    cl.cohort_period,
    cl.user_count,
    cl.host_count,
    cl.listing_count,
    cl.total_ltv,
    COALESCE(cc.total_cac, 0)                                  AS total_cac,
    cl.total_ltv / NULLIF(COALESCE(cc.total_cac, 0), 0)       AS ltv_cac_ratio
FROM cohort_ltv cl
LEFT JOIN cohort_cac cc ON cc.cohort_year = cl.cohort_period
ORDER BY cl.cohort_period

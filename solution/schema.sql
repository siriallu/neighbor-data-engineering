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

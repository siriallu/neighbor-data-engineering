# Data Dictionary

All files are UTF-8 CSV with a header row. Dates are ISO-8601 (`YYYY-MM-DD`). Timestamps are `YYYY-MM-DDTHH:MM:SS` (no timezone — assume UTC).

The dataset covers **2021-05-25 through 2026-05-25** (a 5-year window).

---

## `users_daily_snapshot.csv`

A snapshot of the user table. **Sparse**: a row is emitted on the user's `join_date`, on every day their `state` or `status` changes, and on the last day of the window. To reconstruct the user's attributes on any given date, take the most recent row with `snapshot_date <= target_date`.

| Column | Type | Notes |
|---|---|---|
| `user_id` | string | Primary identifier, e.g. `U00042`. |
| `join_date` | date | The date this user signed up. Does not change. |
| `state` | string | US state code where the user lives (`CA`, `TX`, ...). May change if the user moves. |
| `status` | string | One of `active`, `paused`, `churned`. |
| `acquisition_channel` | string | One of `google_search`, `google_display`, `facebook`, `instagram`, `tiktok`, `referral`, `organic`, or empty (un-attributed). Does not change. |
| `snapshot_date` | date | The date this snapshot row is valid as of. |

Quirks:
- Some users have an **empty** `acquisition_channel` (un-attributed). Treat these and `organic` users as having no associated paid spend.
- A small number of users change `state` mid-period.
- A user may be a host (appears in `listings_daily_snapshot.host_user_id`), a renter (appears in reservation rows), both, or neither.

---

## `listings_daily_snapshot.csv`

Sparse snapshot of the listings table, same pattern as users.

| Column | Type | Notes |
|---|---|---|
| `listing_id` | string | e.g. `L00128`. |
| `host_user_id` | string | FK to `users_daily_snapshot.user_id`. |
| `status` | string | `active` or `inactive`. |
| `city` | string | Listing city. |
| `state` | string | US state code. |
| `monthly_price` | decimal | Listed price per month, USD. |
| `listed_date` | date | The date this listing was first listed. Does not change. |
| `snapshot_date` | date | The date this snapshot row is valid as of. |

Quirks:
- Some listings get deactivated and reactivated over time.
- A user may host multiple listings.
- This table carries the listing's *static* attributes (price, city, etc.) and its status timeline. **The predicted LTV for a listing lives in `listing_predictions.csv`, not here.**

---

## `reservations.csv`

One row per reservation. Reservations are the unit of renter-side activity: a user reserves a listing for some number of months at the listing's monthly price.

| Column | Type | Notes |
|---|---|---|
| `reservation_id` | string | Primary identifier. |
| `user_id` | string | The renter. FK to users. (A user may be the host of *other* listings; we don't constrain a renter from being a host elsewhere.) |
| `listing_id` | string | The listing being reserved. FK to listings. |
| `reservation_date` | date | The day the reservation was created. |
| `duration_months` | integer | How long the renter intends to rent for. |
| `amount` | decimal | Total reservation amount in USD (= `monthly_price * duration_months`). |

Quirks:
- Reservations don't carry an LTV. LTV is a property of the *listing* (the host's side), not the reservation.

---

## `listing_predictions.csv`

One row per listing's predicted host LTV at listing creation. This is the "maximum LTV we expect from this listing over its lifetime" produced by an ML model when the host first lists the space.

| Column | Type | Notes |
|---|---|---|
| `prediction_id` | string | Unique row identifier. |
| `listing_id` | string | FK to listings. |
| `host_ltv` | decimal | Predicted lifetime value for this listing, USD. |
| `model_version` | string | Which model version produced this prediction. |
| `predicted_at` | timestamp | When the prediction was made. |

Quirks:
- In this dataset there is **one prediction per listing** (made on the listing's `listed_date`). In production the model is re-run periodically; assume that is *not* the case here unless told otherwise.
- Treat `host_ltv` as a black-box ML output. Do not attempt to recompute it.

---

## `ad_spend_daily.csv`

Daily ad spend per campaign, with an impressions count and a count of users the marketing platform attributed to that campaign on that day.

| Column | Type | Notes |
|---|---|---|
| `date` | date | The day the spend occurred. |
| `campaign_id` | string | e.g. `C0017`. |
| `campaign_name` | string | Human-readable. |
| `channel` | string | Aligns with `users_daily_snapshot.acquisition_channel` values where applicable (`google_search`, `google_display`, `facebook`, `instagram`, `tiktok`). No rows for `referral` or `organic`. |
| `spend_amount` | decimal | USD spent that day on that campaign. |
| `impressions` | integer | Number of times the ad was shown that day on that campaign. |
| `attributed_signups` | integer | Count of users the platform attributed to this campaign on this date. Can be 0. |

Quirks:
- `attributed_signups` is **noisy** — it comes from upstream marketing platforms and is not always a clean per-user join. Some date/channel cells over-attribute, some under-attribute, and there are windows where signups lag spend.
- Campaigns may run across month boundaries.
- Sum of `attributed_signups` over all rows for a date does not necessarily equal the count of users in `users_daily_snapshot` joining that day on that channel — treat the gap as un-attributable.

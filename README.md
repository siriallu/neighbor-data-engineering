# Neighbor — Data Engineer Take-Home

Welcome, and thanks for the time you're putting into this.

**Time budget: 2 hours.** We tested this internally with our own engineers and they completed it in 2 hours; pace will vary somewhat (some faster, some slower), but please plan around 2 hours and stop there. **Don't push to 3-4 hours to try to finish everything — we'd rather see honest partial work than padded "complete" work.**

We are evaluating *judgment*, not completeness. Pick the parts you can do well, and use a "what I'd do next" section in your README for anything you didn't get to. **A clearly-acknowledged partial does not hurt your score** — we value honesty about what you shipped over a quietly-incomplete submission of similar length.

## Business context

Neighbor is a marketplace for storage rentals: hosts list space (garages, driveways, basements), renters reserve it. We want to report **LTV:CAC** at multiple time grains so the growth and finance teams can see, for each cohort of users, how much we expect them to be worth versus what we paid to acquire them.

### Cohort definition (important — read carefully)

- A "cohort" is the set of users who **joined Neighbor on the same day** (or week, month, year — depending on the grain you're reporting).
- A user's **predicted LTV** is attributed to their **join date**, regardless of when the listing that produced that LTV actually went live.
- Acquisition cost is attributed to the user's **join date**, regardless of when the ad spend that drove that signup actually ran.

So: if a user joined on 2025-08-01, listed a space on 2025-10-12 with a host_ltv of $5,000, then $5,000 is added to the 2025-08-01 cohort's LTV. Time grains are just rollups of the same underlying user-cohort math.

### About LTV (read this twice)

Predicted LTV at Neighbor is computed by an ML model **at the moment a listing is created**, attached to that listing. It's the maximum LTV we expect to extract from the listing over its lifetime — a host-side prediction.

- **Users who never list anything contribute $0 to LTV.** They may still generate realized revenue (by renting on someone else's listing), but that's *realized* revenue, not predicted LTV.
- The LTV:CAC metric uses **predicted host LTV** in the numerator. If you want to layer in realized revenue as a sanity check or alternative cut, you can — but the headline metric is host-side.
- `host_ltv` is denominated in **Neighbor's predicted revenue** from that listing over its lifetime — i.e. the net we keep after paying the host. Treat it as a black-box model output. Do not try to recompute it.

This is a real business reality: storage marketplaces are supply-driven. A single host with a listed space is worth orders of magnitude more than a single renter. The metric reflects that.

## Input data

Five CSV files in `data/`, covering **2021-05-25 through 2026-05-25** (a 5-year window). See `data_dictionary.md` for column-level detail.

- `users_daily_snapshot.csv` — sparse snapshot of users (state/status changes + final).
- `listings_daily_snapshot.csv` — sparse snapshot of listings.
- `reservations.csv` — one row per reservation (user + listing + duration + amount).
- `listing_predictions.csv` — one row per listing's predicted host LTV, with model version and timestamp.
- `ad_spend_daily.csv` — daily spend and impressions per campaign, plus `attributed_signups`.

## Tooling

The data is provided as CSV files. You may load it into whatever environment you prefer (DuckDB, SQLite, Postgres, pandas, etc.). Part of what we're interested in is how you set up your working environment, so use what you'd reach for in real work. **Note your choice and why in your README.**

## Deliverable

Submit a single `.zip` file containing:

1. **DDL** for the data model you designed (the tables you'd build to support LTV:CAC reporting).
2. **SQL queries** that compute LTV:CAC at the following grains:
   - daily (by join date)
   - weekly (by join week)
   - monthly (by join month)
   - yearly (by join year)

   If you don't get to all four grains, ship what you have and note in your README which ones you skipped and why. A monthly + yearly submission with strong reasoning beats a hand-wavy "all four" submission.
3. **A README (max 1 page)** that explains:
   - Your modeling choices and why
   - Your acquisition-cost attribution approach
   - Any assumptions you made about edge cases in the data
   - **Which tools you used** (engine, AI tools) and **why**
   - 2–3 representative prompts you sent to AI tools during the exercise
4. **Setup instructions** sufficient for us to reproduce your results in under 5 minutes.

## On AI tools

We expect you to use AI tools (Claude, ChatGPT, Copilot, whatever you reach for). We're more interested in *how* you collaborated with AI than whether you used it. Include the short prompt section in your README — we're looking for evidence of how you direct, evaluate, and refine AI output, not gotchas.

## Follow-up

If we want to move forward, we'll schedule a 1-hour interview to discuss your solution. In that interview you'll:

- Walk us through your design and the tradeoffs you considered.
- Modify your solution live in response to a small change we'll show you.

## Submitting

See `submission_instructions.md`.

Good luck — we're looking forward to seeing what you build.

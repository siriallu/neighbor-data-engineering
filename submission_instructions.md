# Submission Instructions

## What to send

**Email a single `.zip` file to your recruiter.** Name it `firstname_lastname_neighbor_dataeng.zip` (lowercase, e.g. `jane_doe_neighbor_dataeng.zip`).

Inside the zip:

```
firstname_lastname_neighbor_dataeng/
├── README.md              # max 1 page; modeling choices, tooling, AI usage, prompts
├── ddl/                   # or schema.sql — your model definitions
├── queries/               # SQL files computing LTV:CAC at daily/weekly/monthly/yearly grains
├── setup/                 # any scripts, Makefile, requirements.txt, etc.
└── (optional) results/    # CSVs or screenshots of your query results
```

You can structure things differently — the above is a starting point, not a requirement. Use what's natural for the tooling you picked.

### Please do NOT include in the zip

- The original CSV data files we sent you (we already have them)
- Database binaries (`.duckdb`, `.sqlite`, `.db` files)
- `node_modules/`, `.venv/`, or other dependency folders
- Hidden/system files (`.DS_Store`, `Thumbs.db`)

A clean zip should be well under 1 MB. If yours is larger, double-check what's inside.

## Deadline

Please submit within **7 calendar days** of receiving this package. If you need more time for legitimate reasons (travel, illness, work crunch), email your recruiter — we'd rather give you an extension than receive a rushed submission.

Reply to the original email thread your recruiter sent the take-home in. That way nothing gets lost.

## What happens after you submit

1. Your recruiter will reply within **1 business day** confirming receipt.
2. We'll evaluate your submission within **2-3 business days** of receipt.
3. If we want to move forward, your recruiter will reach out to schedule the 1-hour follow-up interview.

You don't need to send a separate "did you get my submission?" email — if you don't hear back within 2 business days, then check in.

## What we'll do with it

1. Read your README.
2. Follow your setup instructions to load the data and run your queries.
3. Inspect the results and skim the SQL.

If we can't reproduce your results in under 5 minutes from a clean checkout, that's a signal — please make sure the setup works on a fresh machine.

## Time

Please budget **2 hours** for the exercise. We tested this internally with our own engineers and they completed it in roughly 2 hours; pace will vary across candidates, but please plan around 2 hours and stop there. **Don't push to 3-4 hours to try to finish everything.**

If you stop with things unfinished, **say so clearly in your README** — a one-paragraph "I ran out of time on X; here's how I would have approached it" note. A clearly-acknowledged partial does not hurt your score. We'd rather advance an honest engineer who shipped 3 of 4 grains and explained it than a candidate who quietly took twice as long to ship all 4.

If you have to choose between writing one more query and writing the README, write the README. The README is how we evaluate your judgment, and judgment is what we're hiring for.

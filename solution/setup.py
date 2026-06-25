#!/usr/bin/env python3
"""
setup.py -- Neighbor LTV:CAC Pipeline
Requires: pip install duckdb
Run from the project root (where data/ and schema.sql live): python setup.py
"""

import os
import sys
import duckdb

DATA_DIR   = "data"
OUTPUT_DIR = "output"
SCHEMA_SQL = "schema.sql"

REQUIRED_FILES = [
    "users_daily_snapshot.csv",
    "listings_daily_snapshot.csv",
    "listing_predictions.csv",
    "ad_spend_daily.csv",
    "reservations.csv",
]

GRAINS = ["daily", "weekly", "monthly", "yearly"]

CORE_TABLES = [
    "dim_users",
    "fct_listing_ltv",
    "fct_ad_spend_daily",
    "fct_ltv_cac_daily",
    "fct_ltv_cac_weekly",
    "fct_ltv_cac_monthly",
    "fct_ltv_cac_yearly",
]


def preflight():
    print("=== Preflight checks ===")
    if not os.path.isdir(DATA_DIR):
        sys.exit(
            f"ERROR: '{DATA_DIR}/' folder not found.\n"
            "Run this script from the project root (same directory as data/)."
        )
    missing = [
        f for f in REQUIRED_FILES
        if not os.path.isfile(os.path.join(DATA_DIR, f))
    ]
    if missing:
        sys.exit("ERROR: Missing CSV files in data/:\n  " + "\n  ".join(missing))
    print(f"  OK -- all {len(REQUIRED_FILES)} CSV files found in data/")


def build_schema(con: duckdb.DuckDBPyConnection):
    print("\n=== Building tables ===")
    with open(SCHEMA_SQL, "r", encoding="utf-8") as fh:
        sql_text = fh.read()

    statements = [s.strip() for s in sql_text.split(";") if s.strip()]
    for stmt in statements:
        con.execute(stmt)

    for tbl in CORE_TABLES:
        n = con.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
        print(f"  {tbl:<32} {n:>8,} rows")


def export_results(con: duckdb.DuckDBPyConnection):
    print(f"\n=== Exporting results to {OUTPUT_DIR}/ ===")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for grain in GRAINS:
        out_path = os.path.join(OUTPUT_DIR, f"ltv_cac_{grain}.csv")
        # Use forward slashes for DuckDB COPY path on all platforms
        out_path_fwd = out_path.replace("\\", "/")
        con.execute(
            f"COPY (SELECT * FROM fct_ltv_cac_{grain} ORDER BY cohort_period) "
            f"TO '{out_path_fwd}' (HEADER, DELIMITER ',')"
        )
        n = con.execute(f"SELECT COUNT(*) FROM fct_ltv_cac_{grain}").fetchone()[0]
        print(f"  {out_path:<42} ({n} rows)")


def print_summary(con: duckdb.DuckDBPyConnection):
    print("\n=== Summary ===")

    total = con.execute("""
        SELECT
            COUNT(DISTINCT u.user_id)          AS total_users,
            COUNT(DISTINCT l.host_user_id)     AS total_hosts,
            ROUND(SUM(l.host_ltv), 2)          AS total_ltv
        FROM dim_users u
        LEFT JOIN fct_listing_ltv l ON l.host_user_id = u.user_id
    """).fetchone()
    spend = con.execute(
        "SELECT ROUND(SUM(total_spend), 2) FROM fct_ad_spend_daily"
    ).fetchone()[0]

    print(f"  Total users         : {total[0]:>10,}")
    print(f"  Total hosts (w/LTV) : {total[1]:>10,}")
    print(f"  Total LTV (USD)     : {total[2]:>14,.2f}")
    print(f"  Total ad spend (USD): {spend:>14,.2f}")

    print("\n  Yearly LTV:CAC")
    print(f"  {'year':<6} {'users':>7} {'hosts':>7} "
          f"{'total_ltv':>14} {'total_cac':>13} {'ratio':>9}")
    print("  " + "-" * 60)
    rows = con.execute("""
        SELECT
            YEAR(cohort_period),
            user_count,
            host_count,
            ROUND(total_ltv, 2),
            ROUND(total_cac, 2),
            ROUND(ltv_cac_ratio, 4)
        FROM fct_ltv_cac_yearly
        ORDER BY cohort_period
    """).fetchall()
    for r in rows:
        ratio_str = f"{r[5]:.4f}" if r[5] is not None else "  NULL"
        print(f"  {r[0]:<6} {r[1]:>7,} {r[2]:>7,} "
              f"{r[3]:>14,.2f} {r[4]:>13,.2f} {ratio_str:>9}")

    print("\n  Monthly LTV:CAC (first 6 rows)")
    print(f"  {'month':<12} {'users':>7} {'hosts':>7} "
          f"{'total_ltv':>14} {'total_cac':>13} {'ratio':>9}")
    print("  " + "-" * 66)
    rows = con.execute("""
        SELECT
            cohort_period::VARCHAR,
            user_count,
            host_count,
            ROUND(total_ltv, 2),
            ROUND(total_cac, 2),
            ROUND(ltv_cac_ratio, 4)
        FROM fct_ltv_cac_monthly
        ORDER BY cohort_period
        LIMIT 6
    """).fetchall()
    for r in rows:
        ratio_str = f"{r[5]:.4f}" if r[5] is not None else "  NULL"
        print(f"  {r[0]:<12} {r[1]:>7,} {r[2]:>7,} "
              f"{r[3]:>14,.2f} {r[4]:>13,.2f} {ratio_str:>9}")


def main():
    print("Neighbor LTV:CAC Pipeline")
    print("=" * 40)

    # Always run relative to the directory containing this script
    # so schema.sql and data/ are found correctly regardless of where
    # the user invokes python from.
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    preflight()

    print("\n=== Connecting to DuckDB (in-memory) ===")
    con = duckdb.connect(database=":memory:")

    build_schema(con)
    export_results(con)
    print_summary(con)

    con.close()
    print("\nDone. Results are in output/")


if __name__ == "__main__":
    main()

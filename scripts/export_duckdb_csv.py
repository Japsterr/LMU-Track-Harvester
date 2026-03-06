#!/usr/bin/env python3
"""
Export telemetry data from an LMU DuckDB file to a CSV file.

The output CSV uses the LMU Track Harvester column schema:
  TimestampMs, Speed_kmh, RPM, Gear, Throttle_pct, Brake_pct,
  Steering_pct, LapDistance_pct

Usage:
  py -3 export_duckdb_csv.py --input <path_to.duckdb> --output <out.csv>

Requirements:
  pip install duckdb
"""

import argparse
import csv
import sys


# ---------------------------------------------------------------------------
# Column-name mapping helpers
# ---------------------------------------------------------------------------

# Maps the canonical output column name to a priority list of candidate
# input column names (all lower-case; matching is case-insensitive).
COLUMN_CANDIDATES = {
    "TimestampMs":    ["timestamp_ms", "time_ms", "gametime_ms", "game_time_ms",
                       "elapsed_ms", "timestamp", "time"],
    "Speed_kmh":      ["speed_kmh", "speed_kph", "vehicle_speed_kmh",
                       "vehiclespeed_kmh", "speed"],
    "RPM":            ["rpm", "engine_rpm", "enginerpm"],
    "Gear":           ["gear", "current_gear", "currentgear"],
    "Throttle_pct":   ["throttle_pct", "throttle", "gas", "gas_pct",
                       "throttleinput", "throttle_input"],
    "Brake_pct":      ["brake_pct", "brake", "brake_input", "brakeinput"],
    "Steering_pct":   ["steering_pct", "steering", "steering_input",
                       "steeringinput", "steer"],
    "LapDistance_pct": ["lap_dist_pct", "lapdist_pct", "lap_distance_pct",
                        "lap_distance", "lapdistance", "normalized_lap_distance"],
}

# Speed columns that deliver m/s and need a ×3.6 conversion
SPEED_MS_COLUMNS = {"speed"}


def find_column(available_cols: list[str], candidates: list[str]) -> str | None:
    """Return the first candidate found in *available_cols* (case-insensitive)."""
    lower_map = {c.lower(): c for c in available_cols}
    for cand in candidates:
        if cand.lower() in lower_map:
            return lower_map[cand.lower()]
    return None


# ---------------------------------------------------------------------------
# Export logic
# ---------------------------------------------------------------------------

def export(input_path: str, output_path: str) -> None:
    try:
        import duckdb
    except ImportError:
        print(
            "ERROR: The 'duckdb' Python package is not installed.\n"
            "Install it with:  pip install duckdb",
            file=sys.stderr,
        )
        sys.exit(1)

    con = duckdb.connect(input_path, read_only=True)

    # Discover tables
    tables = [row[0] for row in con.execute("SHOW TABLES").fetchall()]
    if not tables:
        print("ERROR: No tables found in the DuckDB file.", file=sys.stderr)
        sys.exit(2)

    # Prefer a table whose name hints at telemetry/data; otherwise use the first
    preferred = None
    for hint in ("telemetry", "data", "lap_data", "samples", "channel"):
        for t in tables:
            if hint in t.lower():
                preferred = t
                break
        if preferred:
            break
    target_table = preferred or tables[0]

    # Introspect columns
    col_info = con.execute(f"DESCRIBE {target_table}").fetchall()
    available_cols = [row[0] for row in col_info]

    # Build column mapping
    col_map: dict[str, str | None] = {}
    for out_col, candidates in COLUMN_CANDIDATES.items():
        col_map[out_col] = find_column(available_cols, candidates)

    missing = [k for k, v in col_map.items() if v is None]
    if missing:
        print(
            f"WARNING: Could not map the following output columns – "
            f"they will be written as empty: {missing}",
            file=sys.stderr,
        )
        print(
            f"Available columns in '{target_table}': {available_cols}",
            file=sys.stderr,
        )

    # Build SELECT
    select_parts = []
    for out_col in COLUMN_CANDIDATES:
        src = col_map[out_col]
        if src is None:
            select_parts.append("NULL")
        else:
            select_parts.append(f'"{src}"')

    query = f"SELECT {', '.join(select_parts)} FROM \"{target_table}\" ORDER BY 1"
    rows = con.execute(query).fetchall()

    if not rows:
        print(
            f"WARNING: Table '{target_table}' contains no rows.", file=sys.stderr
        )

    # Write CSV
    with open(output_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(list(COLUMN_CANDIDATES.keys()))
        for row in rows:
            out_row = list(row)

            # Timestamp: convert to integer ms if it's a float
            if out_row[0] is not None:
                try:
                    out_row[0] = int(float(out_row[0]))
                except (TypeError, ValueError):
                    pass

            # Speed: if the source column is a known m/s column, convert to km/h
            speed_src = col_map.get("Speed_kmh", "")
            if speed_src and speed_src.lower() in SPEED_MS_COLUMNS:
                if out_row[1] is not None:
                    try:
                        out_row[1] = round(float(out_row[1]) * 3.6, 2)
                    except (TypeError, ValueError):
                        pass

            # Throttle/Brake/Steering: normalise 0-1 values to 0-100 pct
            for pct_idx in (4, 5, 6):  # Throttle, Brake, Steering
                val = out_row[pct_idx]
                if val is not None:
                    try:
                        f = float(val)
                        # If value is already in percent range, leave it;
                        # if it's in 0-1 range, multiply by 100
                        if -1.0 <= f <= 1.0:
                            out_row[pct_idx] = round(f * 100.0, 1)
                        else:
                            out_row[pct_idx] = round(f, 1)
                    except (TypeError, ValueError):
                        pass

            writer.writerow(out_row)

    print(f"Exported {len(rows)} row(s) to '{output_path}'.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export LMU DuckDB telemetry to LMU Track Harvester CSV format."
    )
    parser.add_argument("--input",  required=True, help="Path to the .duckdb source file")
    parser.add_argument("--output", required=True, help="Path for the output .csv file")
    args = parser.parse_args()

    try:
        export(args.input, args.output)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

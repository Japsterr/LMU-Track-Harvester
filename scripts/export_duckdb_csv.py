#!/usr/bin/env python3
<<<<<<< HEAD
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
=======
"""Export an LMU DuckDB telemetry file to a single CSV.

The output is a wide CSV aligned by sample index. Column names are prefixed
with the source table name so duplicate names stay unique.
"""

from __future__ import annotations
>>>>>>> c4b932e (Apply fixes: DFM modal values, DuckDB detection, Results XML importer improvements, DuckDB CSV exporter)

import argparse
#!/usr/bin/env python3
"""Export an LMU DuckDB telemetry file to a single CSV.

This exporter writes a wide CSV aligned by sample index. Column names are
prefixed with the source table name when tables contain multiple columns to
avoid collisions.

Usage:
  py -3 export_duckdb_csv.py --input /path/to/source.duckdb --output out.csv

Dependencies:
  pip install duckdb
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    import duckdb
except ModuleNotFoundError:
    print("Missing dependency: duckdb. Install it with: py -3 -m pip install duckdb", file=sys.stderr)
    sys.exit(3)


EXCLUDED_TABLES = {"channelsList", "eventsList", "metadata"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export LMU DuckDB telemetry to CSV")
    parser.add_argument("--input", required=True, help="Path to source .duckdb file")
    parser.add_argument("--output", required=True, help="Destination .csv path")
    return parser.parse_args()


def get_tables(con: duckdb.DuckDBPyConnection) -> list[str]:
    rows = con.execute(
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'main' AND table_type = 'BASE TABLE'
        ORDER BY table_name
        """
    ).fetchall()
    return [row[0] for row in rows if row[0] not in EXCLUDED_TABLES]


def safe_column_name(table_name: str, column_name: str, multi_col: bool) -> str:
    if multi_col:
        return f"{table_name}_{column_name}"
    return column_name


def export_duckdb(input_path: Path, output_path: Path) -> int:
    con = duckdb.connect(str(input_path), read_only=True)
    try:
        tables = get_tables(con)
        if not tables:
            print("No exportable tables found.", file=sys.stderr)
            return 2

        series: list[tuple[str, list[object]]] = []
        max_rows = 0

        for table_name in tables:
            query = f'SELECT * FROM "{table_name}"'
            cursor = con.execute(query)
            rows = cursor.fetchall()
            columns = [desc[0] for desc in cursor.description]
            max_rows = max(max_rows, len(rows))

            if not columns:
                continue

            multi_col = len(columns) > 1
            for index, column_name in enumerate(columns):
                output_name = safe_column_name(table_name, column_name, multi_col)
                values = [row[index] for row in rows]
                series.append((output_name, values))

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["SampleIndex", *[name for name, _ in series]])

            for row_index in range(max_rows):
                row = [row_index]
                for _, values in series:
                    row.append(values[row_index] if row_index < len(values) else "")
                writer.writerow(row)

        return 0
    finally:
        con.close()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    if input_path.suffix.lower() != ".duckdb":
        print(f"Input file is not a .duckdb file: {input_path}", file=sys.stderr)
        return 1

    return export_duckdb(input_path, output_path)


if __name__ == "__main__":
    raise SystemExit(main())
            out_row = list(row)

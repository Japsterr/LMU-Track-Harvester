#!/usr/bin/env python3
"""Read a metadata value from an LMU DuckDB telemetry file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import duckdb
except ModuleNotFoundError:
    print("Missing dependency: duckdb. Install it with: py -3 -m pip install duckdb", file=sys.stderr)
    sys.exit(3)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read a metadata value from an LMU DuckDB file")
    parser.add_argument("--input", required=True, help="Path to source .duckdb file")
    parser.add_argument("--key", required=True, help="Metadata key to read")
    parser.add_argument("--output", required=True, help="Destination text file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    con = duckdb.connect(str(input_path), read_only=True)
    try:
        row = con.execute("SELECT value FROM metadata WHERE key = ?", [args.key]).fetchone()
    finally:
        con.close()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("" if not row or row[0] is None else str(row[0]), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
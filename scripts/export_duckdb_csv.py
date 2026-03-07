#!/usr/bin/env python3
"""Export an LMU DuckDB telemetry file to a canonical CSV.

The output schema matches the app's telemetry CSV format so the file is useful
for external AI analysis and future import workflows.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

try:
    import duckdb
except ModuleNotFoundError:
    print("Missing dependency: duckdb. Install it with: py -3 -m pip install duckdb", file=sys.stderr)
    sys.exit(3)


CHANNEL_MAP = {
    "TimestampMs": "GPS Time",
    "Speed_kmh": "Ground Speed",
    "RPM": "Engine RPM",
    "Gear": "Gear",
    "Throttle_pct": "Throttle Pos",
    "Brake_pct": "Brake Pos",
    "Steering_pct": "Steering Pos",
    "LapDistance_pct": "Lap Dist",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export LMU DuckDB telemetry to CSV")
    parser.add_argument("--input", required=True, help="Path to source .duckdb file")
    parser.add_argument("--output", required=True, help="Destination .csv path")
    return parser.parse_args()


def quote_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def get_tables(con: duckdb.DuckDBPyConnection) -> set[str]:
    return {row[0] for row in con.execute("SHOW TABLES").fetchall()}


def get_channel_frequency(con: duckdb.DuckDBPyConnection, channel_name: str, default: int) -> int:
    row = con.execute(
        "SELECT frequency FROM channelsList WHERE channelName = ?",
        [channel_name],
    ).fetchone()
    if not row or row[0] in (None, 0):
        return default
    return int(row[0])


def read_value_series(con: duckdb.DuckDBPyConnection, table_name: str) -> list[float | int]:
    description = con.execute(f"DESCRIBE {quote_ident(table_name)}").fetchall()
    columns = [row[0] for row in description]
    if not columns:
        return []

    select_column = "value" if "value" in columns else columns[-1]
    rows = con.execute(
        f"SELECT {quote_ident(select_column)} FROM {quote_ident(table_name)}"
    ).fetchall()
    return [row[0] for row in rows]


def resample(values: list[float | int], src_freq: int, base_count: int, base_freq: int) -> list[float | int | str]:
    if base_count <= 0:
        return []
    if not values:
        return [""] * base_count
    if len(values) == base_count:
        return list(values)

    if src_freq <= 0 or base_freq <= 0:
        ratio = len(values) / float(base_count)
    else:
        ratio = src_freq / float(base_freq)

    result: list[float | int | str] = []
    for index in range(base_count):
        src_index = int(math.floor(index * ratio))
        src_index = max(0, min(src_index, len(values) - 1))
        result.append(values[src_index])
    return result


def normalize_percent_series(values: list[float | int | str]) -> list[float | str]:
    numeric = [float(value) for value in values if value != "" and value is not None]
    scale = 100.0 if numeric and max(abs(value) for value in numeric) <= 1.5 else 1.0

    result: list[float | str] = []
    for value in values:
        if value == "" or value is None:
            result.append("")
        else:
            result.append(round(float(value) * scale, 3))
    return result


def normalize_lap_distance(values: list[float | int | str]) -> list[float | str]:
    numeric = [float(value) for value in values if value != "" and value is not None and float(value) >= 0.0]
    if not numeric:
        return [""] * len(values)

    lap_max = max(numeric)
    if lap_max <= 0:
        return [""] * len(values)

    result: list[float | str] = []
    for value in values:
        if value == "" or value is None:
            result.append("")
        else:
            result.append(round(max(0.0, min(1.0, float(value) / lap_max)), 6))
    return result


def build_timestamp_ms(gps_time_values: list[float | int], base_count: int) -> list[int]:
    if not gps_time_values:
        return list(range(base_count))

    start = float(gps_time_values[0])
    trimmed = gps_time_values[:base_count]
    return [int(round((float(value) - start) * 1000.0)) for value in trimmed]


def export_duckdb(input_path: Path, output_path: Path) -> int:
    con = duckdb.connect(str(input_path), read_only=True)
    try:
        tables = get_tables(con)
        if not tables:
            print("No exportable tables found.", file=sys.stderr)
            return 2

        gps_time_values = read_value_series(con, CHANNEL_MAP["TimestampMs"]) if CHANNEL_MAP["TimestampMs"] in tables else []
        base_freq = get_channel_frequency(con, CHANNEL_MAP["TimestampMs"], 100)
        base_count = len(gps_time_values)

        channel_series: dict[str, list[float | int]] = {}
        for output_name, table_name in CHANNEL_MAP.items():
            if table_name not in tables:
                channel_series[output_name] = []
                continue

            values = read_value_series(con, table_name)
            channel_series[output_name] = values
            if output_name != "TimestampMs":
                src_freq = max(get_channel_frequency(con, table_name, base_freq), 1)
                estimated_count = int(math.ceil(len(values) * (base_freq / float(src_freq))))
                base_count = max(base_count, estimated_count)

        if base_count <= 0:
            print("No telemetry samples found in mapped channels.", file=sys.stderr)
            return 2

        timestamps = build_timestamp_ms(
            resample(gps_time_values, base_freq, base_count, base_freq) if gps_time_values else [],
            base_count,
        )

        speed = resample(channel_series.get("Speed_kmh", []), get_channel_frequency(con, CHANNEL_MAP["Speed_kmh"], base_freq), base_count, base_freq)
        rpm = resample(channel_series.get("RPM", []), get_channel_frequency(con, CHANNEL_MAP["RPM"], base_freq), base_count, base_freq)
        gear = resample(channel_series.get("Gear", []), get_channel_frequency(con, CHANNEL_MAP["Gear"], base_freq), base_count, base_freq)
        throttle = normalize_percent_series(
            resample(channel_series.get("Throttle_pct", []), get_channel_frequency(con, CHANNEL_MAP["Throttle_pct"], base_freq), base_count, base_freq)
        )
        brake = normalize_percent_series(
            resample(channel_series.get("Brake_pct", []), get_channel_frequency(con, CHANNEL_MAP["Brake_pct"], base_freq), base_count, base_freq)
        )
        steering = normalize_percent_series(
            resample(channel_series.get("Steering_pct", []), get_channel_frequency(con, CHANNEL_MAP["Steering_pct"], base_freq), base_count, base_freq)
        )
        lap_dist = normalize_lap_distance(
            resample(channel_series.get("LapDistance_pct", []), get_channel_frequency(con, CHANNEL_MAP["LapDistance_pct"], base_freq), base_count, base_freq)
        )

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow([
                "TimestampMs",
                "Speed_kmh",
                "RPM",
                "Gear",
                "Throttle_pct",
                "Brake_pct",
                "Steering_pct",
                "LapDistance_pct",
            ])
            for index in range(base_count):
                writer.writerow([
                    timestamps[index],
                    "" if speed[index] == "" else round(float(speed[index]), 3),
                    "" if rpm[index] == "" else round(float(rpm[index]), 3),
                    "" if gear[index] == "" else int(gear[index]),
                    throttle[index],
                    brake[index],
                    steering[index],
                    lap_dist[index],
                ])
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

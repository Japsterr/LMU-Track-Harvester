#!/usr/bin/env python3
"""Export an LMU DuckDB telemetry file to a canonical CSV.

The first eight columns match the app's legacy telemetry CSV format so existing
imports and local sector analysis continue to work. Additional optional columns
are appended when the LMU source file provides richer channels.
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


BASE_CHANNEL_MAP = {
    "TimestampMs": ("GPS Time",),
    "Speed_kmh": ("Ground Speed",),
    "RPM": ("Engine RPM",),
    "Gear": ("Gear",),
    "Throttle_pct": ("Throttle Pos",),
    "Brake_pct": ("Brake Pos",),
    "Steering_pct": ("Steering Pos",),
    "LapDistance_pct": ("Lap Dist",),
}

EXTRA_SINGLE_CHANNELS = [
    ("GPS_Latitude_deg", ("GPS Latitude",), None),
    ("GPS_Longitude_deg", ("GPS Longitude",), None),
    ("GForceLat_g", ("G Force Lat",), None),
    ("GForceLong_g", ("G Force Long",), None),
    ("GForceVert_g", ("G Force Vert",), None),
    ("FuelLevel", ("Fuel Level",), None),
]

EXTRA_MULTI_CHANNELS = [
    ("BrakeTemp_FL_C", ("Brakes Temp",), "value1", None),
    ("BrakeTemp_FR_C", ("Brakes Temp",), "value2", None),
    ("BrakeTemp_RL_C", ("Brakes Temp",), "value3", None),
    ("BrakeTemp_RR_C", ("Brakes Temp",), "value4", None),
    ("TyreTempL_FL_C", ("TyresTempLeft",), "value1", None),
    ("TyreTempL_FR_C", ("TyresTempLeft",), "value2", None),
    ("TyreTempL_RL_C", ("TyresTempLeft",), "value3", None),
    ("TyreTempL_RR_C", ("TyresTempLeft",), "value4", None),
    ("TyreTempC_FL_C", ("TyresTempCentre",), "value1", None),
    ("TyreTempC_FR_C", ("TyresTempCentre",), "value2", None),
    ("TyreTempC_RL_C", ("TyresTempCentre",), "value3", None),
    ("TyreTempC_RR_C", ("TyresTempCentre",), "value4", None),
    ("TyreTempR_FL_C", ("TyresTempRight",), "value1", None),
    ("TyreTempR_FR_C", ("TyresTempRight",), "value2", None),
    ("TyreTempR_RL_C", ("TyresTempRight",), "value3", None),
    ("TyreTempR_RR_C", ("TyresTempRight",), "value4", None),
    ("TyrePressure_FL", ("TyresPressure",), "value1", None),
    ("TyrePressure_FR", ("TyresPressure",), "value2", None),
    ("TyrePressure_RL", ("TyresPressure",), "value3", None),
    ("TyrePressure_RR", ("TyresPressure",), "value4", None),
    ("TyreWear_FL_pct", ("Tyres Wear", "TyresWear"), "value1", "percent"),
    ("TyreWear_FR_pct", ("Tyres Wear", "TyresWear"), "value2", "percent"),
    ("TyreWear_RL_pct", ("Tyres Wear", "TyresWear"), "value3", "percent"),
    ("TyreWear_RR_pct", ("Tyres Wear", "TyresWear"), "value4", "percent"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export LMU DuckDB telemetry to CSV")
    parser.add_argument("--input", required=True, help="Path to source .duckdb file")
    parser.add_argument("--output", required=True, help="Destination .csv path")
    return parser.parse_args()


def quote_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def get_tables(con: duckdb.DuckDBPyConnection) -> set[str]:
    return {row[0] for row in con.execute("SHOW TABLES").fetchall()}


def find_table_name(tables: set[str], *candidates: str) -> str | None:
    lookup = {table.lower(): table for table in tables}
    for candidate in candidates:
        if candidate in tables:
            return candidate
        actual = lookup.get(candidate.lower())
        if actual:
            return actual
    return None


def get_channel_frequency(con: duckdb.DuckDBPyConnection, channel_name: str, default: int) -> int:
    row = con.execute(
        "SELECT frequency FROM channelsList WHERE channelName = ?",
        [channel_name],
    ).fetchone()
    if not row or row[0] in (None, 0):
        return default
    return int(row[0])


def read_table_series(con: duckdb.DuckDBPyConnection, table_name: str) -> dict[str, list[float | int]]:
    description = con.execute(f"DESCRIBE {quote_ident(table_name)}").fetchall()
    columns = [row[0] for row in description]
    if not columns:
        return {}

    rows = con.execute(
        f"SELECT {', '.join(quote_ident(column) for column in columns)} FROM {quote_ident(table_name)}"
    ).fetchall()
    return {
        column: [row[index] for row in rows]
        for index, column in enumerate(columns)
    }


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


def normalize_passthrough(values: list[float | int | str]) -> list[float | int | str]:
    result: list[float | int | str] = []
    for value in values:
        if value == "" or value is None:
            result.append("")
        else:
            result.append(round(float(value), 6))
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

        resolved_base = {
            output_name: find_table_name(tables, *aliases)
            for output_name, aliases in BASE_CHANNEL_MAP.items()
        }
        series_cache: dict[str, dict[str, list[float | int]]] = {}

        gps_table = resolved_base["TimestampMs"]
        gps_time_values = []
        if gps_table:
            series_cache[gps_table] = read_table_series(con, gps_table)
            gps_time_values = series_cache[gps_table].get("value", [])

        base_freq = get_channel_frequency(con, gps_table, 100) if gps_table else 100
        base_count = len(gps_time_values)

        def ensure_series(table_name: str | None) -> dict[str, list[float | int]]:
            if not table_name:
                return {}
            if table_name not in series_cache:
                series_cache[table_name] = read_table_series(con, table_name)
            return series_cache[table_name]

        def update_base_count(table_name: str | None) -> None:
            nonlocal base_count
            if not table_name:
                return
            table_series = ensure_series(table_name)
            if not table_series:
                return
            longest_series = max((len(values) for values in table_series.values()), default=0)
            src_freq = max(get_channel_frequency(con, table_name, base_freq), 1)
            estimated_count = int(math.ceil(longest_series * (base_freq / float(src_freq))))
            base_count = max(base_count, estimated_count)

        for table_name in resolved_base.values():
            update_base_count(table_name)

        for _, aliases, _ in EXTRA_SINGLE_CHANNELS:
            update_base_count(find_table_name(tables, *aliases))

        for _, aliases, _, _ in EXTRA_MULTI_CHANNELS:
            update_base_count(find_table_name(tables, *aliases))

        if base_count <= 0:
            print("No telemetry samples found in mapped channels.", file=sys.stderr)
            return 2

        timestamps = build_timestamp_ms(
            resample(gps_time_values, base_freq, base_count, base_freq) if gps_time_values else [],
            base_count,
        )

        def resample_column(table_name: str | None, column_name: str | None = None) -> list[float | int | str]:
            if not table_name:
                return [""] * base_count
            table_series = ensure_series(table_name)
            if not table_series:
                return [""] * base_count
            resolved_column = column_name
            if resolved_column is None:
                if "value" in table_series:
                    resolved_column = "value"
                else:
                    resolved_column = next(iter(table_series), None)
            if not resolved_column or resolved_column not in table_series:
                return [""] * base_count
            return resample(
                table_series[resolved_column],
                get_channel_frequency(con, table_name, base_freq),
                base_count,
                base_freq,
            )

        speed = resample_column(resolved_base["Speed_kmh"])
        rpm = resample_column(resolved_base["RPM"])
        gear = resample_column(resolved_base["Gear"])
        throttle = normalize_percent_series(resample_column(resolved_base["Throttle_pct"]))
        brake = normalize_percent_series(resample_column(resolved_base["Brake_pct"]))
        steering = normalize_percent_series(resample_column(resolved_base["Steering_pct"]))
        lap_dist = normalize_lap_distance(resample_column(resolved_base["LapDistance_pct"]))

        extra_series: list[tuple[str, list[float | int | str]]] = []
        for header, aliases, _ in EXTRA_SINGLE_CHANNELS:
            table_name = find_table_name(tables, *aliases)
            extra_series.append((header, normalize_passthrough(resample_column(table_name))))

        for header, aliases, column_name, mode in EXTRA_MULTI_CHANNELS:
            table_name = find_table_name(tables, *aliases)
            values = resample_column(table_name, column_name)
            if mode == "percent":
                values = normalize_percent_series(values)
            else:
                values = normalize_passthrough(values)
            extra_series.append((header, values))

        headers = [
            "TimestampMs",
            "Speed_kmh",
            "RPM",
            "Gear",
            "Throttle_pct",
            "Brake_pct",
            "Steering_pct",
            "LapDistance_pct",
        ] + [header for header, _ in extra_series]

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(headers)
            for index in range(base_count):
                row = [
                    timestamps[index],
                    "" if speed[index] == "" else round(float(speed[index]), 3),
                    "" if rpm[index] == "" else round(float(rpm[index]), 3),
                    "" if gear[index] == "" else int(gear[index]),
                    throttle[index],
                    brake[index],
                    steering[index],
                    lap_dist[index],
                ]
                for _, values in extra_series:
                    row.append(values[index])
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

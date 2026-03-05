#!/usr/bin/env python3
"""
Import extracted laps (CSV produced by parse_results.py) into the LMUTrackHarvester
SQLite database (data.db).

Usage:
  python scripts/import_laps.py --csv parsed/extracted_laps.csv --db "C:\Users\You\Documents\LMUTrackHarvester\data.db"

Behavior:
- Matches track by name (case-insensitive, substring match). If multiple matches, first is used.
- Matches car by exact name (case-insensitive). If not found, inserts the car into `Cars` with a fallback class (creates 'Imported' class if missing).
- Inserts a LapTime row for each CSV row that has a parsable lap_ms value.

Note: Back up your `data.db` before running. This script writes directly to the DB used by the app.
"""

import argparse
import csv
import os
import sqlite3
import sys


def find_track_id(conn, track_name):
    cur = conn.cursor()
    cur.execute("SELECT ID, Name, Layout FROM Tracks")
    candidates = cur.fetchall()
    if not track_name:
        return None
    t = track_name.lower()
    # try exact match on Name or Name + Layout
    for r in candidates:
        name = (r[1] or '').lower()
        layout = (r[2] or '').lower()
        if name == t or (name + ' ' + layout) == t or (name + ' – ' + layout) == t:
            return r[0]
    # try substring
    for r in candidates:
        name = (r[1] or '').lower()
        if t in name:
            return r[0]
    return None


def find_car_id(conn, car_name):
    cur = conn.cursor()
    cur.execute("SELECT ID, Name, ClassID FROM Cars")
    for r in cur.fetchall():
        if (r[1] or '').lower() == (car_name or '').lower():
            return r[0]
    return None


def ensure_imported_class(conn):
    cur = conn.cursor()
    cur.execute("SELECT ID FROM CarClasses WHERE Name = ?", ('Imported',))
    r = cur.fetchone()
    if r:
        return r[0]
    cur.execute("INSERT INTO CarClasses (Name) VALUES (?)", ('Imported',))
    conn.commit()
    return cur.lastrowid


def insert_car(conn, car_name, class_id):
    cur = conn.cursor()
    cur.execute("INSERT INTO Cars (Name, ClassID) VALUES (?, ?)", (car_name, class_id))
    conn.commit()
    return cur.lastrowid


def insert_laptime(conn, track_id, car_id, lap_ms, session_type, lap_date):
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO LapTimes (TrackID, CarID, LapTimeMs, LapDate, SessionType) VALUES (?, ?, ?, ?, ?)",
        (track_id, car_id, lap_ms, lap_date, session_type)
    )
    conn.commit()
    return cur.lastrowid


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', required=True, help='CSV file produced by parse_results.py (extracted_laps.csv)')
    p.add_argument('--db', default=None, help='Path to data.db (default: Documents/LMUTrackHarvester/data.db)')
    p.add_argument('--dry-run', action='store_true', help='Show actions without writing to DB')
    args = p.parse_args()

    csv_path = args.csv
    if not os.path.isfile(csv_path):
        print('CSV not found:', csv_path)
        sys.exit(2)

    if args.db:
        db_path = args.db
    else:
        from pathlib import Path
        doc = Path.home() / 'Documents'
        db_path = str(doc / 'LMUTrackHarvester' / 'data.db')

    if not os.path.isfile(db_path):
        print('Database not found at', db_path)
        print('Provide --db to point to the app database file.')
        sys.exit(3)

    print('Using DB:', db_path)
    conn = sqlite3.connect(db_path)

    imported_class_id = ensure_imported_class(conn)

    with open(csv_path, newline='', encoding='utf-8') as cf:
        reader = csv.DictReader(cf)
        inserted = 0
        for row in reader:
            src = row.get('source_file')
            driver = row.get('driver')
            car = row.get('car') or row.get('Car') or 'Imported Car'
            lap_ms = row.get('lap_ms')
            lap_text = row.get('lap_text')
            timestamp = row.get('timestamp')
            track_guess = None
            # try to guess track from source_file name
            if src:
                # often results filename includes track name; remove extension
                track_guess = os.path.splitext(src)[0]

            # find track id
            track_id = find_track_id(conn, track_guess)
            if track_id is None:
                print('WARNING: no track match for', track_guess, '- skipping row')
                continue

            car_id = find_car_id(conn, car)
            if car_id is None:
                print('Inserting unknown car:', car)
                if args.dry_run:
                    car_id = -1
                else:
                    car_id = insert_car(conn, car, imported_class_id)
                    print('Inserted car id', car_id)

            try:
                lap_ms_val = int(float(lap_ms)) if lap_ms not in (None, '') else None
            except Exception:
                lap_ms_val = None

            if lap_ms_val is None:
                print('Skipping row with no lap_ms:', row)
                continue

            if args.dry_run:
                print('Would insert Lap:', track_id, car_id, lap_ms_val, timestamp)
            else:
                insert_laptime(conn, track_id, car_id, lap_ms_val, 'Imported', timestamp or '')
                inserted += 1

    print('Inserted', inserted, 'lap rows.')
    conn.close()

if __name__ == '__main__':
    main()

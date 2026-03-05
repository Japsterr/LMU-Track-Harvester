#!/usr/bin/env python3
"""
Lightweight Results XML parser for Le Mans Ultimate / rFactor2-style result XML files.

Usage:
  python scripts/parse_results.py --input path/to/Results --out outdir --csv

What it does:
- Recursively converts each XML file to a JSON file (file.json) in the output folder.
- Heuristically extracts lap/time-like nodes and writes a CSV with columns:
  source_file,driver,car,lap_index,lap_text,lap_ms,timestamp,extra

This is intentionally forgiving: it works on many community result XML formats by using
simple heuristics rather than strict schemas.

"""

import argparse
import json
import os
import re
import csv
import sys
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Tuple, Optional

_TIME_RE = re.compile(r"^(?:(\d+):)?(\d{1,2})(?:[\.:](\d{1,3}))$")


def element_to_dict(el: ET.Element) -> Any:
    # If element has no children, return text or attributes
    children = list(el)
    if not children:
        text = el.text.strip() if el.text and el.text.strip() else None
        if el.attrib and text is None:
            return dict(el.attrib)
        if el.attrib and text is not None:
            d = dict(el.attrib)
            d["text"] = text
            return d
        return text if text is not None else (dict(el.attrib) if el.attrib else None)

    result: Dict[str, Any] = {}
    # include attributes if present
    if el.attrib:
        result.update({"@" + k: v for k, v in el.attrib.items()})

    for child in children:
        name = child.tag
        value = element_to_dict(child)
        if name in result:
            # make it a list
            if not isinstance(result[name], list):
                result[name] = [result[name]]
            result[name].append(value)
        else:
            result[name] = value
    return result


def parse_time_to_ms(s: str) -> Optional[int]:
    if s is None:
        return None
    s = s.strip()
    m = _TIME_RE.match(s)
    if m:
        minp = m.group(1)
        sec = m.group(2)
        ms = m.group(3) or '0'
        minutes = int(minp) if minp else 0
        seconds = int(sec)
        millis = int(ms.ljust(3, '0'))
        return minutes * 60000 + seconds * 1000 + millis
    # try pure milliseconds
    if s.isdigit():
        return int(s)
    return None


def find_lap_nodes(root: ET.Element) -> List[ET.Element]:
    result = []
    for el in root.iter():
        tag = el.tag.lower()
        text = (el.text or '').strip()
        # heuristics: tag contains 'lap' or 'time' and text looks like a time
        if 'lap' in tag or 'time' in tag:
            if text:
                if _TIME_RE.search(text) or text.isdigit():
                    result.append(el)
                    continue
        # attributes with time-like values
        for v in el.attrib.values():
            if isinstance(v, str) and (_TIME_RE.search(v) or v.isdigit()):
                result.append(el)
                break
    return result


def nearest_driver_name(el: ET.Element, parent_map: Dict[ET.Element, ET.Element]) -> Optional[str]:
    cur = el
    while cur is not None:
        # look for child named 'Driver' or 'Name' or 'DriverName'
        for child in cur:
            if child.tag.lower() in ('driver', 'drivername'):
                if child.text and child.text.strip():
                    return child.text.strip()
                # or maybe has a Name child
                for g in child:
                    if g.tag.lower() == 'name' and g.text:
                        return g.text.strip()
            if child.tag.lower() == 'name' and child.text:
                return child.text.strip()
        cur = parent_map.get(cur)
    return None


def extract_rows_from_file(path: str) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    tree = ET.parse(path)
    root = tree.getroot()
    # build parent map
    parent_map: Dict[ET.Element, ET.Element] = {c: p for p in tree.iter() for c in p}

    json_obj = {root.tag: element_to_dict(root)}

    lap_nodes = find_lap_nodes(root)
    rows: List[Dict[str, Any]] = []
    for idx, node in enumerate(lap_nodes, start=1):
        text = (node.text or '').strip()
        lap_ms = parse_time_to_ms(text)
        # timestamp attribute if present
        ts = node.attrib.get('Timestamp') or node.attrib.get('timestamp') or node.attrib.get('Time')
        driver = nearest_driver_name(node, parent_map)
        # attempt to find car name in ancestors
        car = None
        cur = node
        while cur is not None:
            for child in cur:
                if child.tag.lower() in ('car', 'carname') and child.text:
                    car = child.text.strip()
                    break
            if car:
                break
            cur = parent_map.get(cur)

        rows.append({
            'lap_index': idx,
            'node_tag': node.tag,
            'lap_text': text,
            'lap_ms': lap_ms,
            'timestamp': ts,
            'driver': driver,
            'car': car,
            'attributes': dict(node.attrib)
        })

    return json_obj, rows


def main():
    p = argparse.ArgumentParser(description='Parse LMU / rFactor-style Results XML files')
    p.add_argument('--input', '-i', required=True, help='Input XML file or directory containing XMLs')
    p.add_argument('--out', '-o', default='out', help='Output folder for JSON/CSV')
    p.add_argument('--csv', action='store_true', help='Also write extracted lap rows to CSV')
    args = p.parse_args()

    inf = args.input
    outdir = args.out
    os.makedirs(outdir, exist_ok=True)

    files = []
    if os.path.isdir(inf):
        for fn in os.listdir(inf):
            if fn.lower().endswith('.xml'):
                files.append(os.path.join(inf, fn))
    elif os.path.isfile(inf):
        files = [inf]
    else:
        print('Input path not found:', inf)
        sys.exit(2)

    all_rows = []
    for f in files:
        try:
            print('Parsing', f)
            json_obj, rows = extract_rows_from_file(f)
            base = os.path.splitext(os.path.basename(f))[0]
            json_path = os.path.join(outdir, base + '.json')
            with open(json_path, 'w', encoding='utf-8') as jf:
                json.dump(json_obj, jf, indent=2, ensure_ascii=False)
            print('Wrote', json_path)
            for r in rows:
                r['source_file'] = os.path.basename(f)
            all_rows.extend(rows)
        except Exception as e:
            print('Failed to parse', f, ':', e)

    if args.csv and all_rows:
        csv_path = os.path.join(outdir, 'extracted_laps.csv')
        keys = ['source_file', 'driver', 'car', 'lap_index', 'lap_text', 'lap_ms', 'timestamp', 'node_tag']
        with open(csv_path, 'w', newline='', encoding='utf-8') as cf:
            writer = csv.DictWriter(cf, fieldnames=keys)
            writer.writeheader()
            for r in all_rows:
                row = {k: r.get(k) for k in keys}
                writer.writerow(row)
        print('Wrote CSV:', csv_path)


if __name__ == '__main__':
    main()

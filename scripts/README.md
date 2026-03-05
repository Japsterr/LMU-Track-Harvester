Results XML parser

This small utility parses Le Mans Ultimate / rFactor2-style Results XML files.

Usage examples:

# Parse a single file and output JSON
python scripts/parse_results.py --input "C:\Path\To\Results\race_001.xml" --out parsed --csv

# Parse all XML files in a folder and write JSON + extracted CSV
python scripts/parse_results.py --input "C:\Path\To\Results" --out parsed --csv

Outputs:
- For each XML file: `out/<basename>.json` — JSON representation of the XML.
- If `--csv` is used and lap-like nodes are found: `out/extracted_laps.csv` — heuristic rows with columns: source_file, driver, car, lap_index, lap_text, lap_ms, timestamp.

Notes:
- The parser uses heuristics to find lap/time nodes; it is intentionally forgiving to handle multiple community XML formats.
- If you want a strict parser for a particular XML schema, provide a sample result XML and I can adapt the extraction to match the exact structure.

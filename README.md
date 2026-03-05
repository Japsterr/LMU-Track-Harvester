# LMU Track Harvester

A **Delphi VCL desktop application** for tracking personal lap times and
analysing telemetry in the racing simulation game
[Le Mans Ultimate](https://www.le-mans-ultimate.com/).

---

## Features

### 🏁 Lap Times
* Select any **track / circuit** and **car class** (Hypercar, LMP2, LMGT3)
* View your **Top 10 personal-best laps** for that combination
* View the **fastest recorded lap per individual car** in a class
* **Add** lap times manually (track, car, time, date, session type)
* **Delete** lap times
* **Export** lap time tables to CSV

### 📊 Telemetry
* **Import** telemetry sessions from CSV files
* Manage a library of saved sessions (track, car, date, data-point count)
* **Export** any session back to CSV for use in external tools or AI models
* **Analyse with Gemini AI** — send the telemetry CSV directly to Google
  Gemini inside the app and receive structured coaching feedback:
  * Braking analysis
  * Throttle application
  * Gear selection
  * Steering inputs
  * Top 3 areas to improve

### ⚙️ Settings
* Store your **Google Gemini API key** (saved locally in `settings.ini`)
* Choose the AI model (`gemini-1.5-flash`, `gemini-1.5-pro`,
  `gemini-2.0-flash`, etc.)
* Configure the **LMU telemetry source folder** (auto-defaults to
  `SteamLibrary\steamapps\common\Le Mans Ultimate\UserData\Telemetry`)
  so telemetry import browsing opens in the correct location and `.duckdb`
  source files are discoverable in the Telemetry list
* Configure the **LMU results source folder** (auto-defaults to
  `SteamLibrary\steamapps\common\Le Mans Ultimate\UserData\Log\Results`)
  so `.xml` results files are scanned and new lap records are imported into
  the local database for display in Lap Times grids
* One-click **Test Connection** button to verify your API key works
* Link to get a free API key at [aistudio.google.com](https://aistudio.google.com/app/apikey)

---

## Pre-seeded data

On first run the app seeds the SQLite database with:

**Tracks** – all circuits on the 2024 WEC calendar (Le Mans, Monza, Spa,
Fuji, Bahrain, Portimão, Sebring, Road Atlanta, Lusail, Interlagos, Imola,
Yas Marina, Barcelona, Lédenon)

**Car classes** – Hypercar · LMP2 · LMGT3

**Cars** – all manufacturers competing in each class (Ferrari, Toyota,
Porsche, Cadillac, BMW, Peugeot, Alpine, Lamborghini, Isotta Fraschini,
ORECA, Aston Martin, Ford, McLaren, Corvette, Lexus, Mercedes-AMG, etc.)

---

## Requirements

| Component | Version |
|-----------|---------|
| Embarcadero Delphi | 10.4 Sydney or later (tested with Delphi 11 Alexandria) |
| FireDAC | Included with Delphi (SQLite driver) |
| System.Net.HttpClient | Included with Delphi 10.3+ |

No third-party libraries or NuGet/npm packages are required.

---

## Building

1. Open **`LMUTrackHarvester.dproj`** in the Delphi IDE.
2. Ensure the **FireDAC SQLite** driver is installed (it ships with Delphi by default).
3. Press **F9** (Run) or **Shift+F9** (Compile) to build.

The compiled executable will be placed in `Win32\Debug\` or `Win32\Release\`
depending on the active build configuration.

### First-time setup

No database or configuration file is needed before running – both are created
automatically in `%DOCUMENTS%\LMUTrackHarvester\` on first launch.

---

## Telemetry CSV Format

When importing telemetry data the CSV file must have this header row followed
by data rows:

```
TimestampMs,Speed_kmh,RPM,Gear,Throttle_pct,Brake_pct,Steering_pct,LapDistance_pct
```

| Column | Description |
|--------|-------------|
| `TimestampMs` | Milliseconds since session start |
| `Speed_kmh` | Vehicle speed in km/h |
| `RPM` | Engine RPM |
| `Gear` | Current gear (0 = neutral) |
| `Throttle_pct` | Throttle input 0–100 |
| `Brake_pct` | Brake input 0–100 |
| `Steering_pct` | Steering angle –100 (full left) to +100 (full right) |
| `LapDistance_pct` | Fraction of lap completed 0.0–1.0 |

The app also exports data in exactly this format, so sessions can be
round-tripped or shared.

---

## Data Storage

All data is stored in a local SQLite database (default location):

```
%DOCUMENTS%\LMUTrackHarvester\data.db
```

If the Documents folder is unavailable/unwritable, database creation falls back to another user-writable location.

Settings are stored in (default location):

```
%DOCUMENTS%\LMUTrackHarvester\settings.ini
```

If the Documents folder is unavailable/unwritable, settings storage falls back to another user-writable location.

Your Gemini API key is **never** transmitted anywhere except to
`generativelanguage.googleapis.com` when you click *Analyse with Gemini AI*.

---

## Planned Features

* [ ] In-game overlay / network display (later phase)
* [ ] Live telemetry capture via the rFactor 2 / LMU shared-memory API
* [ ] Session comparison (overlay two telemetry sessions on a chart)
* [ ] Custom track / car management UI

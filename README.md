# LMU Track Harvester

LMU Track Harvester is a desktop companion for Le Mans Ultimate built around a simple outcome: make your lap history and telemetry useful enough that you can actually improve from it.

It gives you one place to track your best laps, review LMU results, organize telemetry, export clean coaching-ready CSV files, and send a session to Gemini for driving feedback.

## Quick Download Guide

If you are sharing this project with testers, point them to the release downloads:

* [Download the installer (LMUTrackHarvester-Installer.exe)](https://github.com/Japsterr/LMU-Track-Harvester/raw/main/download/LMUTrackHarvester-Installer.exe) for the simplest install-style setup
* [Download the portable zip (LMUTrackHarvester-Portable.zip)](https://github.com/Japsterr/LMU-Track-Harvester/raw/main/download/LMUTrackHarvester-Portable.zip) for users who want the files directly

For most people, the installer is the easiest option.

If someone is browsing the repository and clicking the files inside the `download` folder does not start a download, use the direct links above instead.

## What Testers Should Expect

The app itself runs without Python being installed.

If the release includes a bundled portable Python runtime, LMU source `.duckdb` telemetry helpers also work out of the box, including:

* reading track, car, and driver metadata from LMU telemetry files
* exporting LMU source telemetry directly to CSV for coaching

If a release does not include bundled Python, the main app still works, but those LMU `.duckdb` helper features will need Python plus `duckdb` on the tester machine.

## Why Drivers Use It

Most LMU data ends up spread across result files, telemetry folders, spreadsheets, and ad hoc exports. LMU Track Harvester brings those pieces together into one workflow:

1. Track your own best laps by track, class, and car.
2. Bring LMU result files into a clean personal pace library.
3. Browse telemetry sessions and LMU source telemetry files without digging through folders.
4. Export a structured CSV that is ready for AI coaching or manual analysis.
5. Review visual summaries inside the app before you ever leave it.

For many drivers, the biggest value is very direct: you can see your best lap times clearly, then export telemetry to get advice on how to improve them.

## Main Features

### Best lap tracking

The lap-time section is the core performance notebook.

You can:

* see your best laps by track and class
* view a personal top-10 pace board
* see the fastest lap you have recorded for each car in a class
* add manual lap entries when you want to keep offline or historical records
* delete unwanted entries
* export lap tables to CSV

This makes it easy to answer the two questions most drivers care about: what is my best lap here, and which car has given me my best result?

### LMU results import

The app scans LMU results XML files and imports laps for the chosen driver only, so your pace library stays focused on your own running instead of everyone from a server session.

It also tracks imported files so normal rescans do not need to rebuild everything from scratch.

### Telemetry garage

The telemetry section is built as a working garage, not just a raw file browser.

You can:

* import telemetry CSV sessions
* browse saved telemetry sessions inside the app
* browse LMU `.duckdb` source telemetry files directly
* keep telemetry grouped with track, car, driver, and timing context
* rescan LMU telemetry sources with metadata caching so the app does not keep doing the old slow full reads

### Visual session review

Before exporting anything, the app already gives you a quick in-app review layer:

* sector scorecards
* a track map preview
* telemetry traces
* session detail notes

That means you can spot rough trends immediately, then decide whether a deeper export or AI pass is worth doing.

### CSV export for coaching

One of the strongest workflows in the app is the clean export path.

With a selected telemetry session or LMU source file, you can export a CSV that is ready to:

* inspect in Excel or another data tool
* share with another driver or coach
* feed into an AI coaching workflow

The export is designed to make the jump from raw telemetry to usable feedback as short as possible.

### Gemini coaching

Once telemetry is selected, the app can send it to Gemini and ask for structured coaching feedback.

The intent is practical guidance, not generic commentary. Typical feedback focuses on:

* braking behavior
* throttle use
* steering inputs
* gear choices
* likely time-loss areas or focus corners

That gives you a fast loop from session to advice to next stint.

## Typical Workflow

1. Run a session in LMU.
2. Let LMU Track Harvester pick up your result files and telemetry sources.
3. Review your best lap times and session summaries.
4. Export telemetry CSV for a chosen lap or session.
5. Use Gemini or another analysis flow to get concrete improvement advice.

This is the part of the app that tends to matter most in practice: your best laps are visible, and your telemetry is easy to export for coaching.

## For Testers

Releases are built for two common tester paths:

* `download\LMUTrackHarvester-Installer.exe` for the simplest setup
* `download\LMUTrackHarvester-Portable.zip` for a direct portable package

### What works even without Python

If no bundled portable Python runtime is included, testers can still use the app for:

* viewing stored lap data
* importing LMU results XML files
* working with already imported telemetry CSV sessions
* browsing the app UI and its local database features

### What bundled Python unlocks

Direct LMU source telemetry helper features rely on the bundled Python scripts in the `scripts` folder.

Those features include:

* reading LMU `.duckdb` metadata such as track, car, and driver
* exporting LMU `.duckdb` telemetry directly to coaching-ready CSV

For those features to work on tester machines that do not have Python installed, place a portable runtime in one of these folders before building downloads:

* `python\python.exe`
* `runtime\python\python.exe`

Then run `build_downloads.ps1`.

When a portable runtime is present, the installer and zip include it automatically. When it is not present, the build still succeeds, but LMU DuckDB helper features will still depend on Python plus `duckdb` being available on the tester machine.

## Release Packaging

The release scripts now package the current main build and tell you whether bundled Python was detected.

* `bundle_release.ps1` creates the staged portable release in `dist\`
* `build_downloads.ps1` creates the GitHub-ready downloads in `download\`

If a bundled runtime is found, the scripts report that the LMU DuckDB helper flow is portable. If not, they emit a warning so the limitation is obvious at build time instead of being discovered by testers later.

## What Makes It Valuable

LMU Track Harvester is most useful when you treat it as a practical improvement tool, not just a data viewer.

It helps by giving you one place to:

* keep your best lap history
* review LMU results cleanly
* organize telemetry sessions
* export a clean CSV for coaching
* turn telemetry into feedback you can act on

For a driver trying to get faster with less friction, that is the point of the app.

# Change Log

## Bug Fixes (Current Session)

### Fix 1 – EXMLDocError when scanning/importing Results XML files

**Files changed:** `ResultsXMLImporter.pas`

**Problem:**  
`EXMLDocError: Element "rFactorXML" does not contain a single text node`  
was thrown inside `WalkNodeForLaps` at the line:

```pascal
NodeText := Trim(ANode.Text);
```

Delphi's `IXMLNode.Text` property raises `EXMLDocError` whenever the node
contains child *element* nodes rather than a single text value.  The root
`rFactorXML` element (and many inner elements) in Le Mans Ultimate result
files always have child elements, never plain text, so this exception fired
for every element in the tree.

Because the exception propagated through the entire recursive
`WalkNodeForLaps` call stack before being caught by the outer `try/except`
in `ImportFolder`, **no lap candidates were ever extracted from any file**
and no lap times were inserted into the database.  The GExperts debugger
surfaced this as a notification every time the app opened or the user
triggered a manual rescan.

**Fix (two locations):**

1. **`WalkNodeForLaps`** – wrapped the `ANode.Text` call in a
   `try/except on EXMLDocError` block; on failure `NodeText` defaults to
   `''`.  The rest of the function (attribute walking, recursive child
   walking) continues normally so the full XML tree is processed.

2. **`ReadNodeValue`** – wrapped the `Child.Text` call in the same guard so
   that matching child elements whose own content is a sub-tree (rather than
   a leaf text node) do not propagate an exception.

---

### Fix 2 – "+ Add Lap Time" dialog – defensive creation and error reporting

**Files changed:** `MainForm.pas`

**Problem:**  
`TAddLapForm.Create(Self)` in `TMainForm.BtnAddLapClick` could raise an
exception (form-resource or database error) with no user-friendly handling.
The exception propagated unhandled, causing a raw Delphi/GExperts exception
dialog and leaving the UI in an inconsistent state.

**Fix:**

* Added `if not Assigned(FDB)` guard before attempting to create the dialog,
  so that a missing database gives an immediately understandable message.
* Changed the `try/finally` to `try/except/end` with an explicit
  `on E: Exception do ShowMessage(...)` so that *any* exception during form
  creation or initialisation is presented as a readable message instead of an
  unhandled crash.
* Initialised `Dlg := nil` before the `try` block so the form is released
  correctly even if `Create` throws.

---

### Fix 3 – Wrap `ImportResultsFromConfiguredFolder` in error handling

**Files changed:** `MainForm.pas`

**Problem:**  
`ImportResultsFromConfiguredFolder` called `TResultsXMLImporter.ImportFolder`
without any outer exception guard.  An unexpected error (e.g. from
`TDirectory.GetFiles` on a restricted path) would propagate to `FormCreate`
and prevent the main window from loading.

**Fix:**  
Wrapped the `ImportFolder` call in `try/except`; if the call raises, the
error is shown to the user (when `AShowStatus = True`) or silently skipped
(silent startup scan), and the procedure returns early.

---

### Fix 4 – Add `ResultsXMLImporter` to project files

**Files changed:** `LMUTrackHarvester.dpr`, `LMUTrackHarvester.dproj`

`ResultsXMLImporter.pas` was used by `MainForm` but was not listed in the
`.dpr` uses clause or the `.dproj` `<DCCReference>` list.  Added the unit to
both files so the Delphi IDE correctly tracks it as part of the project.

---

## Summary of Files Changed

| File | Change |
|------|--------|
| `ResultsXMLImporter.pas` | Protect `ANode.Text` in `WalkNodeForLaps`; protect `Child.Text` in `ReadNodeValue` |
| `MainForm.pas` | Defensive `BtnAddLapClick` (try/except + FDB guard); wrap `ImportResultsFromConfiguredFolder` |
| `LMUTrackHarvester.dpr` | Add `ResultsXMLImporter` to uses clause |
| `LMUTrackHarvester.dproj` | Add `ResultsXMLImporter` DCCReference |
| `CHANGES.md` | This file |

### Fix 5 - Win64-native release packaging, branding hook, and signing support

**Files changed:** `bundle_release.ps1`, `build_downloads.ps1`, `build_release.cmd`, `build_debug.cmd`, `build_release_alt.cmd`, `packaging_common.ps1`, `prepare_branding.ps1`, `branding/README.md`, `branding/icon-generation-prompt.txt`, `README.md`

**Problem:**
The release scripts still assumed the old Win32 plus Python packaging flow even after the app moved to native DuckDB through `duckdb.dll` and the project default moved to Win64. That meant release artifacts could be built from the wrong platform, omit `duckdb.dll`, keep stale Python messaging, and provide no structured path for a proper EXE icon or optional code signing.

**Fix:**

1. Changed the packaging scripts to target `Win64` only and bundle `duckdb.dll` from the repository root.
2. Removed stale portable-Python packaging logic and messaging from the release/download flow.
3. Added `prepare_branding.ps1` plus `branding\app-icon.ico` conventions so scripted builds can regenerate `LMUTrackHarvester.res` and apply a real app icon before compile.
4. Added optional signing support in the packaging scripts using `signtool.exe` and environment-driven certificate configuration.
5. Updated the installer build so it reuses the same branding icon when `branding\app-icon.ico` exists.
6. Documented the icon asset brief, generation prompt, and signing usage for releases.

### Fix 6 - Correct LMU source telemetry lap shaping and cache preview rows in SQLite

**Files changed:** `DuckDBNative.pas`, `CSVExporter.pas`, `DatabaseManager.pas`, `MainForm.pas`

**Problem:**
LMU `.duckdb` source previews were being shaped with a broken assumption: channels were aligned using frequency metadata rather than a shared timeline, and `Lap Dist` was treated like a session-wide 0..1 fraction instead of a per-lap distance channel. That produced obviously wrong sector times, broken representative-lap detection, poor track-map output, and repeated source preview regeneration on every selection.

**Fix:**

1. Switched the preview/export shaping logic to use `GPS Time` as the canonical timeline when available.
2. Changed continuous channel resampling to align against that shared time-base by row count instead of relying on LMU per-channel frequency metadata for visual preview alignment.
3. Normalized `Lap Dist` by detecting real raw lap resets and scaling each lap segment independently, which restored realistic lap durations and sector timing.
4. Included GPS latitude/longitude in source previews so the track map can render from real coordinates instead of the steering-based fallback path.
5. Added a shared telemetry CSV parser in `CSVExporter.pas`.
6. Added `TelemetrySourcePreviewData` in SQLite and wired source selection to reuse cached normalized preview rows when the source file timestamp has not changed.

# Branding Assets

Place your Windows app icon at `branding\app-icon.ico`.

The release build scripts will detect that file automatically and regenerate `LMUTrackHarvester.res` before compiling. That updates the main EXE icon. The installer build also uses the same `.ico` for its own executable icon when present.

## What to generate

Ask your designer or image generator for two files:

1. `app-icon-1024.png`
   * square canvas
   * 1024 x 1024 pixels
   * transparent background preferred
   * bold simple shape that still reads at small sizes
   * no tiny text, no thin outlines, no photo detail

2. `app-icon.ico`
   * multi-size Windows icon exported from the master PNG
   * include at least: 16, 20, 24, 32, 40, 48, 64, 128, 256 px
   * 32-bit RGBA with transparency

## Image brief

The icon should feel like motorsport telemetry software, not a generic folder or tool icon.

Visual direction:

* racing line or apex motif
* telemetry trace, track outline, or timing delta cue
* strong silhouette that survives at 16 px
* limited palette, high contrast
* no screenshots, no text labels, no detailed car render

## Prompt template

Use the text in `branding\icon-generation-prompt.txt` as the starting brief for an image model or a designer.

## Apply the icon manually

If you want to regenerate the Delphi project resource yourself without running the build script:

```powershell
powershell -ExecutionPolicy Bypass -File .\prepare_branding.ps1
```

That overwrites `LMUTrackHarvester.res` with a `MAINICON` resource compiled from `branding\app-icon.ico`.
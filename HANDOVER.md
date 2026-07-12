# Project Handover — Photosynthesis

Freetown drone orthophoto (single 118GB COG, ~4cm/px) → PMTiles via the Mapterhorn pipeline
(`mapterhorn/` submodule/nested repo), run on an **8-core / 8GB RAM** machine.

## Current status (2026-07-13)

Aggregation is running unattended and producing verified-correct output (visually confirmed
real drone imagery, not corrupted/blank). Downsampling has been smoke-tested and is queued to
auto-start once aggregation finishes. A full code review of this session's changes has been
done; findings below.

### Root causes fixed this session (in the order they were actually found)

1. **Unbounded worker pools**: `aggregation_run.py` used bare `multiprocessing.Pool()` = one
   worker per core (8), each running `gdal_translate`/`rasterio` on large rasters — exhausted
   8GB RAM and crashed the machine. Fixed via `get_worker_count()` reading `AGGREGATION_WORKERS`
   (default 4).

2. **`macrotile_z`/`child_z` gap with no ceiling** (the deeper blocker): `utils.macrotile_z = 12`
   with `num_overviews = 6` only capped how far aggregation tiles merge *coarser*; nothing
   capped a source's native-resolution zoom (`child_z`) exceeding `macrotile_z` on the *fine*
   side. This source's 4cm/px resolution computes `child_z=21` — a 9-level gap — which made
   `aggregation_reproject.py` try to materialize 262144×262144px rasters (~256GiB) per tile.
   **Fix**: raised `macrotile_z` 12→**17**, bringing the gap to 6 (32768px/side, ~4GB, matching
   the pipeline's originally-documented safe max). Re-ran covering: 9 grossly-oversized items →
   187 properly-sized ones.

3. **`source_polygonize.py`'s coverage mask was silently wrong**: `gdal_calc.py -A source.tif
   --calc="A*0+1"` doesn't consult the source's internal `PER_DATASET` mask (no NoData *value*
   is set) — verified empirically, it marked pure-black pixels as "valid". Running
   `gdal_polygonize.py` on the resulting always-1 130GB mask was pure waste and never finished.
   **Fix**: replaced with a single `gdal_footprint` call (GDAL 3.13) that reads the real mask.
   Also found and fixed a second bug in the same area: `merge_source()`'s union SQL assumed a
   layer named `out`, but only got renamed to that on the 2nd+ file in a multi-file merge —
   single-source projects (like this one) always produced an empty coverage polygon. Fixed by
   adding `-nln out` to the first file's copy too. Verified: real 1-feature polygon, ~97-98% of
   the bounding box, matches a plausible drone-survey footprint.

4. **`aggregation_tile.py` crashed on every single item's first output tile**: used
   `np.float32` without `import numpy as np`. This is why ~150 items reached the expensive
   reproject step (each ~3GB) but zero ever completed — the crash happened right after,
   silently leaking 155GB of orphaned tmp folders instead of erroring visibly. Fixed by adding
   the import (and dropping a redundant full-resolution `dataset_mask()` probe that was reading
   the whole mask array just to check truthiness, which `dataset_mask()` never fails).

### Verification performed

- Aggregation output: visually inspected real tiles via a local PMTiles server + custom raster
  viewer (`rgb_viewer.html`, since the repo's own `website/viewer/index.html` is hardcoded for
  `raster-dem`/Terrarium hillshade rendering and would misinterpret RGB pixels as elevation) —
  confirmed real rooftops/roads/vegetation, not noise or blank tiles.
- Downsampling: smoke-tested twice in isolation (calling `downsampling_run.main([single_csv])`
  directly on already-completed aggregation tiles, without waiting for the full run) — both
  produced real, visually-verified 2×2-averaged output. Also fixed `validate_pixels.py`, which
  was sampling tile coordinates near the world origin (0-3, 0-3) instead of the archive's real
  z21 coordinates (~971000s for Freetown) and always reported "no tiles found" on real data.

### Orchestration built for unattended operation

- `auto_aggregation.sh` — disk-safety-monitored `aggregation_run.py` launcher (superseded by
  `monitor_running_aggregation.sh` for the currently-running instance, but fixed and usable for
  future runs — see code review below).
- `monitor_running_aggregation.sh` — attaches to an already-running `aggregation_run.py`,
  aborts on <20GB free disk, logs to `auto_aggregation.log` every 5 min. **Currently running.**
- `auto_downsampling.sh` — waits for aggregation to reach 187/187 done (polls every 2 min),
  then runs `downsampling_covering.py` + `DOWNSAMPLING_WORKERS=4 downsampling_run.py` with the
  same disk-safety monitoring. **Currently running (in its wait loop).**
- `check_progress.py`, `monitor_progress.py`, `validate_pixels.py` — fixed to work with the
  current dynamic `aggregation_id` (were hardcoded to a stale one from an earlier attempt).

### Code review findings (2026-07-13, high-effort multi-angle review of this session's diff)

Fixed (safe — files not actively running, or edits don't affect an already-imported process):
- `check_progress.py`: `if current:` treated 0 completed downsampling items as "not started"
  (falsy-zero bug) — now `if current is not None:`.
- `monitor_progress.py`: timestamp parsing assumed microseconds are always present; Python's
  `datetime.now()` omits them when exactly 0, causing a silently-swallowed `IndexError` that
  drops that log entry from rate/ETA calculations.
- `rgb_viewer.html`: hash-param parser split on every `=`, truncating any URL value containing
  `=` (e.g. a signed URL) — now splits only on the first `=`.
- `auto_aggregation.sh`: done-count `find` wasn't scoped to the current `aggregation_id` (would
  double-count if a stale aggregation-store directory coexists — this exact situation happened
  earlier this session), and the per-iteration log line hardcoded the total as `187`. Now
  resolves `$AGG_ID` and `$TOTAL` dynamically.
- `aggregation_run.py`: `AGGREGATION_WORKERS=0` (or negative) passed validation and crashed
  `Pool(processes=0)` instead of falling back to the default. Now guards `value >= 1`.

**Not fixed yet — worth doing next session:**
- **`monitor_running_aggregation.sh` / `auto_aggregation.sh`'s disk-safety `pkill -TERM -f
  "aggregation_run.py"` may not actually stop work on macOS.** `multiprocessing.Pool` uses the
  `spawn` start method there, so worker child processes' command lines don't contain
  `aggregation_run.py` — only the parent dies. The `gdal_translate` processes get a second,
  separate `pkill` by their own command-line pattern, which covers the actual disk-writing step
  for *already-started* items, but a worker that survives could pick up a new item and start
  writing again before the next 5-minute poll. Consider `pkill -f
  "multiprocessing.*aggregation_run"` or tracking child PIDs explicitly.
- **Same `pkill -f "aggregation_run.py"` is an unanchored substring match** — would also kill
  an unrelated `vim aggregation_run.py` or `grep -rn aggregation_run.py .` running at the wrong
  moment. Low probability, easy to tighten with an anchored pattern if revisited.
- **The disk-safety while-loop (df parse + threshold + pkill) is duplicated near-identically
  across `auto_aggregation.sh`, `auto_downsampling.sh`, and `monitor_running_aggregation.sh`.**
  A future threshold/behavior change applied to only some of the three leaves a real safety
  gap. Should be one sourced shell function.
- **`bundle.py`'s `child_z <= 12` branch (routes tiles into a global `planet.pmtiles` bucket)
  is now permanently dead code**, since `aggregation_covering.py` forces every source's
  `maxzoom` to `>= macrotile_z` (now 17) via `max(maxzoom, utils.macrotile_z)`. Benign for this
  single high-res source (it correctly always takes the regional-bucket branch instead), but
  worth knowing before `bundle.py` runs, and would matter if a low-resolution source is ever
  added to the same project.
- **`source_polygonize.py`'s `gdal_footprint` call dropped the explicit band-1 pinning** the
  old `gdal_calc` approach had — footprint now depends on GDAL's default mask/band selection.
  Currently verified correct for this single RGB source; would need re-checking if a
  multi-band source with inconsistent per-band nodata is ever added.
- `get_worker_count()` is duplicated verbatim between `aggregation_run.py` and
  `downsampling_run.py`; `AGGREGATION_WORKERS`/`DOWNSAMPLING_WORKERS` are independent env vars
  with no shared awareness of the combined 8GB RAM budget — currently safe in practice because
  `auto_downsampling.sh` waits for aggregation to fully finish before starting downsampling
  (never concurrent), but nothing enforces that if run manually.

### Known latent issue (not fixed, not currently blocking)

`aggregation_reproject.py`'s `contains_nodata_pixels()` and `aggregation_merge.py`'s blending
have the same NoData-value-only blind spot as the old polygonize step (never check
`dataset_mask()`/alpha) — but that code path only runs when blending *multiple* overlapping
sources, and this project has exactly one source. Revisit if a second overlapping source is
ever added.

## Why Mapterhorn instead of geotiff-to-pmtiles or gdal2tiles.py

See `ANALYSIS.md` for the full comparison. Short version: geotiff-to-pmtiles can't read this
source (internal DEFLATE codec bug, independent of GDAL); gdal2tiles.py works but has no
incremental-update model. Mapterhorn was adapted instead — Lanczos resampling (was
`cubicspline`), RGB WebP output (was Terrarium elevation encoding), NaN/contiguity fixes —
before this session's zoom-gap, NoData, and NameError fixes.

## Machine / environment notes

- 8 cores, **8GB RAM** — the binding constraint behind almost every crash this project has had.
  Any new parallel stage needs an explicit worker cap from day one, not added after a crash.
- Disk fluctuates in the 20–175GB free range on this volume as intermediates are
  generated/cleaned — the orchestration scripts abort automatically below 20GB free.
- Python env: `mapterhorn/pipelines/.venv` (uv-managed). Plain `python`/`python3` on PATH may
  not resolve correctly in a fresh shell — always `source .venv/bin/activate` first.
- GDAL 3.13 (homebrew) has `gdal_footprint` available — prefer it over hand-rolled
  `gdal_calc`+`gdal_polygonize` combos for any future coverage/mask work.
- `mapterhorn/website/viewer/index.html` (the repo's own PMTiles viewer) is hardcoded for
  terrain hillshade rendering (`raster-dem` + Terrarium encoding) — do not use it to check RGB
  orthophoto output, it will render nonsense. Use `pipelines/rgb_viewer.html` instead (serve
  both it and `pmtiles serve pmtiles-store` locally; see chat history for the exact commands).

## Next steps

1. Aggregation is running unattended (187 items, ~1.8 min/item, ETA a few hours from whenever
   this is read — check `auto_aggregation.log` / `check_progress.py`).
2. `auto_downsampling.sh` will auto-start once aggregation hits 187/187 — no action needed.
3. Once both complete cleanly, commit the remaining uncommitted `mapterhorn` submodule changes
   (source_polygonize.py's `-nln out` fix, aggregation_tile.py's NameError fix were already
   committed; the check_progress.py/monitor_progress.py/rgb_viewer.html/auto_*.sh fixes from
   this code-review pass are not yet committed).
4. `bundle.py` once downsampling has real coverage — reads `dirty_only = False` (bundles
   everything, not just changed regions) per an earlier session's deliberate choice to include
   new downsampling tiles; this makes every bundle run O(all tiles) rather than incremental,
   worth knowing if it's slow.
5. Consider addressing the "not fixed yet" code-review items above, especially the macOS
   `pkill` spawn-mode gap, before relying on the disk-safety monitors unattended for
   much longer stretches.

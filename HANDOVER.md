# Project Handover — Photosynthesis

Freetown drone orthophoto (single 118GB COG, ~4cm/px) → PMTiles via the Mapterhorn pipeline
(`mapterhorn/` submodule/nested repo), run on an **8-core / 8GB RAM** machine.

## Status: complete and live (2026-07-14)

The full pipeline ran end-to-end: Source → Aggregation (187/187) → Downsampling (519/519) →
Bundle → merge → upload → serving. Final artifact is live at:

```
https://stars.optgeo.org/?tab=tiles&inspect=freetown-mapterhorn&underlay=dark#map=11.28/8.4569/-13.222
```

- `mapterhorn/pipelines/bundle-store/freetown-mapterhorn.pmtiles` (13.7GB, z0-z21, 1,021,309
  tiles, verified with `pmtiles verify` and pixel-content spot checks at every zoom level —
  no missing zoom levels, no corruption) is the single merged archive: `bundle.py` itself
  produces two files (`planet.pmtiles` for z≤12 global overview + `6-29-30.pmtiles` for
  z13-21 regional detail — see "Bundle output shape" below for why), merged into one via
  `mapterhorn/pipelines/merge_bundles.py` (the `pmtiles merge` CLI subcommand exists in the
  installed `go-pmtiles` 1.28.0 but panics when actually invoked — use the Python script
  instead, it streams tiles rather than loading the 13.7GB source into memory).
- Uploaded via `rsync` to `stars.local:/home/stars/data/` (sizes verified identical on both
  ends), then `systemctl --user restart martin` on stars.local to pick it up. SSH access to
  stars.local now uses a dedicated key (`~/.ssh/id_ed25519_stars`, `Host stars.local` entry in
  `~/.ssh/config`, user `stars`) instead of password auth.
- **Attribution fix**: the first upload's metadata copied `bundle.py`'s generic default
  attribution verbatim (a link to `mapterhorn.com/attribution`, the upstream Mapterhorn
  project's own multi-source catalog page — unrelated to this derived single-source archive).
  Looked up the real source via OAM's search API (`api.openaerialmap.org/meta?bbox=...` — the
  direct `imagery/{id}`/`meta/{id}` lookups both errored, search-by-bbox worked): "Freetown
  Urban with Sensitive Areas Blurred" by Ivan Gayton / DroneTM / HOTOSM. The record has no
  explicit license field, so OAM's platform default (CC-BY 4.0) applies, which requires
  attribution. Fixed in `merge_bundles.py`, regenerated, and re-uploaded.

## Root causes fixed this session, in the order actually found

1. **Unbounded worker pools**: `aggregation_run.py` used bare `multiprocessing.Pool()` = one
   worker per core (8), each running `gdal_translate`/`rasterio` on large rasters — exhausted
   8GB RAM and crashed the machine. Fixed via `get_worker_count()` reading `AGGREGATION_WORKERS`
   (default 4).

2. **`macrotile_z`/`child_z` gap with no ceiling** (the deeper blocker): `utils.macrotile_z = 12`
   with `num_overviews = 6` only capped how far aggregation tiles merge *coarser*; nothing
   capped a source's native-resolution zoom (`child_z`) exceeding `macrotile_z` on the *fine*
   side. This source's 4cm/px resolution computes `child_z=21` — a 9-level gap — which made
   `aggregation_reproject.py` try to materialize 262144×262144px rasters (~256GiB) per tile.
   **Fix**: raised `macrotile_z` 12→**17**, bringing the gap to 6 (32768px/side, ~4GB). Covering
   went from 9 grossly-oversized items (all z12) to 187 properly-sized ones (all z15).

3. **`source_polygonize.py`'s coverage mask was silently wrong**: `gdal_calc.py -A source.tif
   --calc="A*0+1"` doesn't consult the source's internal `PER_DATASET` mask (no NoData *value*
   is set) — verified empirically, it marked pure-black pixels as "valid". Running
   `gdal_polygonize.py` on the resulting always-1 130GB mask was pure waste and never finished.
   **Fix**: replaced with a single `gdal_footprint` call (GDAL 3.13) that reads the real mask.
   Also found a second bug in the same area: `merge_source()`'s union SQL assumed a layer named
   `out`, but only got renamed to that on the 2nd+ file in a multi-file merge — single-source
   projects (like this one) always produced an empty coverage polygon. Fixed by adding
   `-nln out` to the first file's copy too. Verified: real 1-feature polygon, ~97-98% of the
   bounding box.

4. **`aggregation_tile.py` crashed on every single item's first output tile**: used
   `np.float32` without `import numpy as np`. This is why ~150 items reached the expensive
   reproject step (each ~3GB) but zero ever completed — the crash happened right after,
   silently leaking 155GB of orphaned tmp folders instead of erroring visibly. Fixed by adding
   the import (and dropping a redundant full-resolution `dataset_mask()` probe).

5. **Downsampling processing order silently dropped pyramid data.** `sort_files_by_proximity()`
   sorted by the wrong zoom variable (`z`, the coarse covering-extent zoom, constant per
   extent) instead of `child_zoom` (the actual output level being built). This let a coarser
   level get built before the finer level it depends on existed. `create_tile()` silently skips
   any missing referenced PMTiles file (treats it as blank) and marks the item `.done`
   unconditionally regardless — so an out-of-order build produces a *permanently* incomplete
   tile with no retry. Caught mid-run at 44/519 items (5 "not found" warnings already logged).
   Stopped the run, cleared all downsampling `.done` markers and outputs, fixed the sort key to
   `(-child_zoom, distance)`, restarted clean. Verified: zero "not found" warnings for the rest
   of the 519-item run.

## Verification performed

- Aggregation and downsampling output: visually inspected via a local PMTiles server
  (`pmtiles serve`) + custom raster viewer (`pipelines/rgb_viewer.html`) — confirmed real
  rooftops/roads/vegetation at multiple zoom levels, not noise or blank tiles. The repo's own
  `website/viewer/index.html` is hardcoded for `raster-dem`/Terrarium hillshade rendering and
  will misinterpret RGB pixels as elevation — don't use it for this kind of output.
- `validate_pixels.py` (fixed this session — see below) pixel-sampled output at every pipeline
  stage. Two recurring false-negative patterns worth knowing about if you see "empty" reports
  that seem surprising: (a) fixed 20-tile stride sampling can miss real content that's sparse
  or geographically clustered within a large archive — always full-scan-verify before trusting
  a "BAD" result; (b) the `< 1024 bytes ⇒ "too small"` size heuristic false-flags legitimate
  low-zoom global tiles (z0-z5), which can be a real, correct, mostly-transparent single-region
  dot compressed to a few hundred bytes.
- Final merged `freetown-mapterhorn.pmtiles`: confirmed all 22 zoom levels (0-21) have tiles,
  tile-count growth ratio is a clean 4x/level from z16 up (matching 2×2 pyramid math), total
  tile count matches `pmtiles show`'s `addressed_tiles_count` exactly (1,021,309).

## Bundle output shape (why 2 files, and how they got merged)

`bundle.py`'s `get_parent_to_filepaths()` routes every `pmtiles-store` archive by the zoom
embedded in its filename: `child_z <= 12` → the single global `mercantile.Tile(0,0,0)` bucket
(`planet.pmtiles`); `child_z >= 13` → a regional bucket keyed by the z6 parent tile (here, one
bucket, `6-29-30.pmtiles`, since Freetown fits inside a single z6 tile). This is *not* dead
code — earlier in this session a comment was mistakenly added claiming the `<=12` branch was
unreachable (reasoning only about aggregation output, which is always `child_z=21` here) without
accounting for downsampling, which legitimately produces archives all the way down to z1. The
comment was corrected once this was noticed. Since this project wanted one deployable file
instead of two, `pipelines/merge_bundles.py` streams both `bundle-store` outputs into
`freetown-mapterhorn.pmtiles` (concatenation is safe without re-sorting because tile IDs are
strictly increasing with zoom, and the two files' zoom ranges don't overlap).

## Known non-blocking limitations (not fixed, low current risk)

- **`pkill`-based process termination in the disk-safety scripts may not catch every worker on
  macOS.** `multiprocessing.Pool` uses the `spawn` start method there, so worker child
  processes' command lines don't contain the launching script's name — `pkill -f
  "aggregation_run.py"` only kills the parent. Fixed in `auto_aggregation.sh` (now sourced from
  `pipelines/disk_safety_guard.sh`, which kills the whole process group via `kill -TERM --
  -$PGID` instead — verified empirically on a throwaway multiprocessing test that this catches
  spawn workers where `pkill -f` did not). The specific `monitor_running_aggregation.sh` /
  `auto_downsampling.sh` instances used during this session's actual run were **not** hot-patched
  to the new mechanism (they were live processes; editing a running bash script is risky) — they
  used the old pattern for this run and it happened not to matter (disk stayed healthy
  throughout), but any future long unattended run should use `auto_aggregation.sh` (already
  fixed) and should port `auto_downsampling.sh`/`monitor_running_aggregation.sh` to
  `disk_safety_guard.sh` too before relying on them.
- `source_polygonize.py`'s `gdal_footprint` call has no explicit band pinning (the old
  `gdal_calc` approach pinned band 1) — footprint now depends on GDAL's default mask/band
  selection. Verified correct for this single RGB source; would need re-checking for a
  multi-band source with inconsistent per-band nodata.
- `get_worker_count()` is duplicated between `aggregation_run.py` and `downsampling_run.py`;
  `AGGREGATION_WORKERS`/`DOWNSAMPLING_WORKERS` have no shared awareness of the combined 8GB
  budget. Currently safe because the two stages never ran concurrently, but nothing enforces
  that if run manually.
- `aggregation_reproject.py`'s `contains_nodata_pixels()` and `aggregation_merge.py`'s blending
  have a NoData-*value*-only blind spot (never check `dataset_mask()`/alpha), same class of bug
  as the original polygonize issue — but this code path only runs when blending *multiple*
  overlapping sources, and this project has exactly one. Revisit if a second overlapping source
  is ever added.

## Why Mapterhorn instead of geotiff-to-pmtiles or gdal2tiles.py

See `ANALYSIS.md` for the full comparison. Short version: geotiff-to-pmtiles can't read this
source (internal DEFLATE codec bug, independent of GDAL); gdal2tiles.py works but has no
incremental-update model. Mapterhorn was adapted instead — Lanczos resampling (was
`cubicspline`), RGB WebP output (was Terrarium elevation encoding), NaN/contiguity fixes —
before this session's zoom-gap, NoData, NameError, and downsampling-order fixes.

## Machine / environment notes

- 8 cores, **8GB RAM** — the binding constraint behind almost every crash this project has had.
  Any new parallel stage needs an explicit worker cap from day one, not added after a crash.
- Python env: `mapterhorn/pipelines/.venv` (uv-managed). Plain `python`/`python3` on PATH may
  not resolve correctly in a fresh shell — always `source .venv/bin/activate` first.
- GDAL 3.13 (homebrew) has `gdal_footprint` available — prefer it over hand-rolled
  `gdal_calc`+`gdal_polygonize` combos for any future coverage/mask work.
- `pmtiles` CLI (go-pmtiles 1.28.0, `/usr/local/bin/pmtiles`) — `merge` is listed in its
  subcommand help but panics when run; use `pipelines/merge_bundles.py` instead.
- SSH to `stars.local`: dedicated key at `~/.ssh/id_ed25519_stars`, configured in
  `~/.ssh/config`, connects as user `stars`. Upload target: `/home/stars/data/`. Tile server is
  `martin`, managed via `systemctl --user restart martin` on stars.local.

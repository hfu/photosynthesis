# Project Handover — Photosynthesis

Freetown drone orthophoto (single 118GB COG, ~4cm/px) → PMTiles via the Mapterhorn pipeline
(`mapterhorn/` submodule/nested repo), run on an **8-core / 8GB RAM** machine.

## Current status (2026-07-12, evening session)

The pipeline had crashed the OS repeatedly. This session diagnosed and fixed the two root
causes. Aggregation has just been re-planned with the fix and is about to be re-run; not yet
verified end-to-end.

### What was wrong

1. **Unbounded worker pools** (fixed earlier, before this session's deeper investigation):
   `aggregation_run.py` used bare `multiprocessing.Pool()` = one worker per core (8), each
   running `gdal_translate`/`rasterio` on large rasters — exhausted 8GB RAM and crashed the
   machine. Fixed by adding `get_worker_count()` (mirrors the pattern already in
   `downsampling_run.py`), defaulting to 4, overridable via `AGGREGATION_WORKERS`.

2. **`macrotile_z`/`child_z` gap with no ceiling** (the deeper, actual blocker): Mapterhorn's
   `utils.py` has `macrotile_z = 12` (the base tiling grid) and `num_overviews = 6` (how far
   aggregation tiles can be merged *coarser*). Nothing capped how far a source's native-resolution
   zoom (`child_z`, computed purely from pixel size) could exceed `macrotile_z` on the *fine*
   side. This source's 4cm/px resolution computes to `child_z=21` — a 9-level gap — which made
   `aggregation_reproject.py` try to materialize a 262144×262144px raster (up to ~256GiB) per
   aggregation tile. That's what filled disk and crashed the machine, every time, before a
   single aggregation item ever completed (confirmed: 0 `.done` files across every prior
   attempt logged in `pipelines/aggregation.log`).

   **Fix**: raised `utils.macrotile_z` from 12 → **17** in `mapterhorn/pipelines/utils.py`.
   This lets the covering algorithm (`aggregation_covering.py`'s `get_aggregation_tiles_dfs`)
   find aggregation tiles at z15 (the coarsest zoom satisfying
   `candidate.z >= maxzoom(21) - num_overviews(6)`), giving a gap of 6 → 32768px/side tiles
   (~4GB uncompressed, matching the pipeline README's originally-documented safe maximum).
   Re-ran `aggregation_covering.py`: went from 9 grossly-oversized items (all z12) to 187
   properly-sized items (all z15, child_z21).

3. **`source_polygonize.py`'s coverage mask was silently wrong**: it ran
   `gdal_calc.py -A source.tif --calc="A*0+1"` to build a "valid data" mask, then
   `gdal_polygonize.py` to vectorize it. The source has no NoData *value* set on its bands
   (only an internal `Mask Flags: PER_DATASET` alpha-style mask), and `gdal_calc.py` doesn't
   consult that internal mask — verified empirically (a crop of pure-black source pixels still
   produced `Minimum=1, Maximum=1` in the output). So the "mask" was a trivial always-1
   rectangle, and running `gdal_polygonize.py` against the full 140-billion-pixel raster to
   vectorize a shape already known to be a rectangle was pure waste — 130GB, and it never
   finished (found as a corrupted leftover file from an earlier interrupted run; deleted,
   reclaimed 130GB).

   **Fix**: replaced `polygonize_tif()` with a single `gdal_footprint` call directly on the
   source tif (GDAL 3.13, already installed via homebrew). It reads the real internal mask
   instead of guessing from pixel color, without ever materializing a full-resolution
   intermediate mask file.

### Files changed this session

- `mapterhorn/pipelines/utils.py` — `macrotile_z: 12 → 17`
- `mapterhorn/pipelines/source_polygonize.py` — `polygonize_tif()` now calls `gdal_footprint`
  directly instead of `gdal_calc.py` + `gdal_polygonize.py`
- `mapterhorn/pipelines/aggregation_run.py` — worker cap (`AGGREGATION_WORKERS`, default 4) —
  from the earlier part of this session, still uncommitted
- Cleaned up: corrupted 130GB `polygon-store/freetown/*.tif` mask, obsolete
  `aggregation-store/01KXAXQ6DFQ5RXTY8MPH1TE4SX/` (old z12 planning, 0 items ever completed)

None of the above is committed to the `mapterhorn` submodule yet — verify end-to-end first.

### In progress / not yet verified

- `source_polygonize.py freetown 1` running in background with the new `gdal_footprint`
  approach — first real-world timing/correctness check of this fix (it was only validated
  against a corrupted mask file before, which correctly returned empty — that proves it
  doesn't hallucinate on garbage input, not that it works on the real 118GB source).
- Aggregation has **not yet been re-run** with the new 187-item, z15 planning. Next step:
  `AGGREGATION_WORKERS=4 python aggregation_run.py`, monitor disk headroom and `.done` count
  the same way this session did for the diagnosis.
- Downsampling and bundle stages untouched this session — downsampling had earlier produced a
  handful of tiles in `pmtiles-store/7-59-60/` and `7-59-61/` from a pre-crash run; those
  predate the aggregation fix and should be treated as stale once real aggregation output
  exists.

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
before this session's zoom-gap and NoData fixes.

## Machine / environment notes

- 8 cores, **8GB RAM** — this is the binding constraint behind almost every crash so far.
  Any new parallel stage needs an explicit worker cap from day one, not added after a crash.
- Disk fluctuates in the 40–175GB free range on this volume as intermediates are
  generated/cleaned — watch it before starting any stage that materializes large rasters.
- Python env: `mapterhorn/pipelines/.venv` (uv-managed). Plain `python`/`python3` on PATH may
  not resolve correctly in a fresh shell — always `source .venv/bin/activate` first.
- GDAL 3.13 (homebrew) has `gdal_footprint` available — useful for any future coverage/mask
  work, prefer it over hand-rolled `gdal_calc`+`gdal_polygonize` combos.

## Next steps

1. Confirm `source_polygonize.py freetown 1` finished with a real (non-empty, non-rectangular
   unless the source genuinely has no padding) footprint in reasonable time.
2. `AGGREGATION_WORKERS=4 python aggregation_run.py`, monitor disk + `.done` count, confirm at
   least one item completes and produces a real (not placeholder-sized) `pmtiles-store/` file.
3. If aggregation completes cleanly, commit the `mapterhorn` submodule changes.
4. Re-run downsampling from scratch against the new aggregation output.
5. `bundle.py` once downsampling has real coverage.

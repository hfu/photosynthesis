# Photosynthesis: Freetown Orthophoto → PMTiles

**Project Status**: ✅ Complete and live. Full pipeline run (Source → Aggregation → Downsampling
→ Bundle), merged into a single archive, uploaded, and served:
https://stars.optgeo.org/?tab=tiles&inspect=freetown-mapterhorn&underlay=dark#map=11.28/8.4569/-13.222
See `HANDOVER.md` for the full debugging history and known limitations.

Converting a single high-resolution drone orthophoto of Freetown, Sierra Leone (OpenAerialMap)
into web-servable PMTiles, using the Mapterhorn pipeline (originally built for DEM/elevation
data, adapted here for RGB orthophoto imagery).

## Source Data

- **File**: `mapterhorn/pipelines/source-store/freetown/690585b76415e43597ffd7eb.tif`
- **Format**: Cloud Optimized GeoTIFF, DEFLATE-compressed, 3-band RGB (~118 GB)
- **Dimensions**: 486,906 × 287,291 pixels
- **Resolution**: ~0.0394 m/pixel (~4 cm) — mercator zoom 21 equivalent
- **Coordinate System**: WGS 84 / UTM zone 28N (EPSG:32628)
- **Location**: Freetown, Sierra Leone

## Why Mapterhorn (not geotiff-to-pmtiles)

Two other tools were evaluated first and rejected — see `ANALYSIS.md` for the full comparison:

- **geotiff-to-pmtiles**: has an internal DEFLATE-reader bug that fails on this source's
  compression, independent of GDAL (which reads the same file fine).
- **gdal2tiles.py + pmtiles**: viable but single-source only, no incremental updates.

Mapterhorn was chosen for its incremental-update model and Lanczos/WebP support, at the cost
of being architected for elevation data — several of its assumptions (zoom-gap limits, NoData
handling) don't hold for a single, ultra-high-resolution orthophoto and needed patching. That
patching is the bulk of the work tracked in `HANDOVER.md`.

## Machine constraints

This runs on an 8-core / **8 GB RAM** machine with limited disk (~45–175 GB free, fluctuates
as intermediates are generated/cleaned). Every pipeline stage's parallelism must be capped
explicitly (`AGGREGATION_WORKERS`, `DOWNSAMPLING_WORKERS` env vars) — unbounded
`multiprocessing.Pool()` has crashed the OS more than once this project.

## Running the pipeline

```bash
cd mapterhorn/pipelines
source .venv/bin/activate

python source_bounds.py freetown        # bounds.csv from the source tif
python source_polygonize.py freetown 1  # coverage polygon via gdal_footprint
python aggregation_covering.py          # plan aggregation tiles
AGGREGATION_WORKERS=4 python aggregation_run.py
python downsampling_covering.py
DOWNSAMPLING_WORKERS=4 python downsampling_run.py
python bundle.py 1
python merge_bundles.py                 # planet.pmtiles + regional -> one archive
```

Full stage-by-stage documentation lives in `mapterhorn/pipelines/README.md` (submodule,
upstream Mapterhorn docs — accurate for the generic pipeline; this repo's `HANDOVER.md`
documents where and why this project deviates from it).

`bundle.py` produces two files (a global low-zoom `planet.pmtiles` and a regional
high-detail archive) by design; `merge_bundles.py` streams them into one deployable
`freetown-mapterhorn.pmtiles` (the `pmtiles merge` CLI subcommand exists but panics in the
installed go-pmtiles 1.28.0 — don't use it).

## Files

- **HANDOVER.md** — session-by-session history, current state, next steps
- **ANALYSIS.md** — tool comparison research (geotiff-to-pmtiles vs gdal2tiles vs Mapterhorn)
- **MAPTERHORN_SETUP.md** — project-specific setup notes for this source
- **DIRECTORY_STRUCTURE.md** — repo layout

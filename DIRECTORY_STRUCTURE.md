# Project Directory Structure

```
photosynthesis/
│
├── src/
│   ├── 690585b76415e43597ffd7eb.tif    (GeoTIFF source - ~15 GB)
│   └── 690585b76415e43597ffd7eb.tif.aria2  (download metadata)
│
├── dst/
│   ├── geotiff-to-pmtiles/
│   │   ├── freetown_bilinear_avif75.pmtiles
│   │   └── freetown_nearest_png.pmtiles
│   │
│   └── mapterhorn/
│       ├── freetown_lanczos_webp.pmtiles
│       └── (other Mapterhorn outputs)
│
├── geotiff-to-pmtiles/          (submodule/clone)
│   ├── src/
│   ├── target/
│   │   └── release/
│   │       └── geotiff-to-pmtiles  (binary)
│   ├── Cargo.toml
│   └── ...
│
├── mapterhorn/                  (submodule/clone)
│   ├── pipelines/
│   │   ├── aggregation_*.py
│   │   ├── downsampling_*.py
│   │   ├── bundle.py
│   │   └── ...
│   └── ...
│
├── Justfile
├── .gitignore
├── ANALYSIS.md
├── README.md (to be created)
└── HANDOVER.md (to be created)
```

## Directory Purpose

- **src/**: Input GeoTIFF source files
  - Large files (~ 15 GB+)
  - Excluded from git via .gitignore

- **dst/**: Output PMTiles files organized by tool
  - `geotiff-to-pmtiles/`: Simple CLI conversion outputs
  - `mapterhorn/`: Complex pipeline outputs
  - All files excluded from git (stored on stars)

- **geotiff-to-pmtiles/**: Tool repository
  - Pre-built binary in `target/release/`
  - Excluded from git (external dependency)

- **mapterhorn/**: Pipeline repository
  - Python-based multi-stage pipeline
  - Excluded from git (external dependency)

## File Naming Convention

**geotiff-to-pmtiles outputs**:
```
freetown_{resampling}_{format}{quality}.pmtiles
  - freetown_bilinear_avif75.pmtiles
  - freetown_nearest_png.pmtiles
```

**Mapterhorn outputs** (future):
```
freetown_{resampling}_{format}.pmtiles
  - freetown_lanczos_webp.pmtiles
```

## .gitignore Strategy

Excluded patterns:
- `*.pmtiles` - All PMTiles files (stored on stars)
- `*.tif`, `*.tiff` - GeoTIFF source files (already on S3)
- `dst/` - Entire output directory
- `target/` - Build artifacts
- Standard patterns (Python, IDE, OS)


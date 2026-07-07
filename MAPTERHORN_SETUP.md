# Mapterhorn Pipeline Setup for Freetown Imagery Evaluation

## Environment Setup

✅ **Completed**:
- uv installed
- Python 3.13.14 virtual environment created
- All dependencies installed (rasterio, pyproj, pmtiles, scipy, imagecodecs, etc.)

## Required Directory Structure

```
mapterhorn/
├── pipelines/
│   ├── .venv/                    (Python environment)
│   ├── source-store/             (Input GeoTIFF files by source)
│   │   └── freetown/
│   │       └── 690585b76415e43597ffd7eb.tif
│   │
│   ├── source-catalog/           (Source metadata)
│   │   └── freetown.json         (source configuration)
│   │
│   ├── aggregation-store/        (Intermediate aggregation tiles)
│   ├── pmtiles-store/            (Output PMTiles by tool)
│   │   └── freetown_lanczos_webp.pmtiles
│   │
│   └── bundle-store/             (Final bundled PMTiles)
```

## Pipeline Stages

### Stage 1: Source Preparation
- Copy GeoTIFF to `source-store/freetown/`
- Create bounds.csv
- Polygonize coverage
- Create tarball

### Stage 2: Aggregation
- Compute coverage (macrotiles)
- Reproject to Web Mercator
- Merge sources
- Encode to WebP (Terrarium RGB)

### Stage 3: Downsampling
- Create zoom level overviews
- 2×2 averaging
- Re-encode as WebP

### Stage 4: Bundle
- Combine single-zoom PMTiles
- Create multi-zoom pyramids

## Freetown Imagery Configuration

### Source Details
- **Name**: freetown
- **Input**: `/Users/hfu/photosynthesis/src/690585b76415e43597ffd7eb.tif`
- **Format**: GeoTIFF (JPEG-in-TIFF, YCbCr JPEG Quality 75)
- **Size**: 14 GB
- **CRS**: WGS 84 / UTM zone 28N (EPSG:32628)
- **Resolution**: 0.0394 m/pixel (~4 cm)
- **Dimensions**: 486,906 × 287,291 pixels

### Expected Resampling: Lanczos (via GDAL)
- **Better than**: Nearest + Bilinear
- **Quality**: Production-grade
- **Encoding**: WebP (Terrarium RGB)
- **Vertical Resolution**: Zoom-dependent (0.149m at Z19)

## Quick Start

### 1. Prepare Source Directory
```bash
cd /Users/hfu/photosynthesis/mapterhorn/pipelines
mkdir -p source-store/freetown
cp /Users/hfu/photosynthesis/src/690585b76415e43597ffd7eb.tif source-store/freetown/
```

### 2. Create Source Bounds
```bash
.venv/bin/python source_bounds.py freetown
```
Creates `source-store/freetown/bounds.csv`

### 3. Polygonize Coverage
```bash
.venv/bin/python source_polygonize.py freetown
```
Creates `polygon-store/freetown.gpkg`

### 4. Run Aggregation Covering
```bash
.venv/bin/python aggregation_covering.py
```
Plans which macrotiles need processing

### 5. Run Aggregation
```bash
.venv/bin/python aggregation_run.py
```
Main processing stage:
- GDAL VRT + Warp + Reproject
- Web Mercator projection
- Lanczos resampling (implicit via GDAL)
- WebP encoding (Terrarium RGB)

### 6. Run Downsampling
```bash
.venv/bin/python downsampling_covering.py
.venv/bin/python downsampling_run.py
```
Creates zoom level overviews

### 7. Bundle Results
```bash
TMPDIR=/tmp .venv/bin/python bundle.py 1
```
Combines into multi-zoom PMTiles

### 8. Inspect Results
```bash
ls -lh pmtiles-store/
.venv/bin/pmtiles-show pmtiles-store/7-67-44/12-2144-1434-17.pmtiles
```

## Key Differences from geotiff-to-pmtiles

| Aspect | geotiff-to-pmtiles | Mapterhorn |
|--------|-------------------|-----------|
| **Resampling** | Bilinear only | Lanczos (via GDAL) |
| **Format Support** | JPEG-in-TIFF ❌ | JPEG-in-TIFF ✅ |
| **Scale** | Single image | Multi-source blending |
| **Encoding** | AVIF, PNG, WebP | WebP (Terrarium) |
| **Processing** | Single pass | 4-stage pipeline |
| **Time** | ~30 min | ~2-4 hours |
| **Memory** | ~2 GB | ~2 GB per thread |

## Expected Output

After successful pipeline run:
- **Primary output**: `pmtiles-store/7-67-44/12-2144-1434-17.pmtiles` (and related tiles)
- **File size**: Varies by zoom range
- **Format**: PMTiles v3 with Terrarium RGB WebP tiles
- **Tile size**: 512×512 pixels
- **Zoom levels**: 0-19 (depending on source resolution)

## Notes

### Processing Time
- Source bounds: ~5 min
- Polygonize: ~10 min
- Aggregation covering: ~5 min
- Aggregation run (main): 1-2 hours
- Downsampling: ~1 hour
- Bundle: ~30 min
- **Total**: ~3-4 hours

### Disk Space
- Input: 14 GB
- Intermediate (aggregation-store, source-store): ~40 GB
- Output (pmtiles-store): ~2-5 GB
- **Total needed**: ~60 GB

### Hardware
- CPU: Will use multiple cores (parallelization)
- RAM: Recommend 16+ GB
- Disk: SSD for source-store and aggregation-store (random access)

## Troubleshooting

### Common Issues
1. **GDAL errors**: Ensure GDAL 3.x installed
   ```bash
   gdalinfo --version
   ```

2. **Memory errors**: Reduce parallelization or increase available RAM

3. **Disk errors**: Ensure source-store is on SSD

4. **Python path issues**: Use `.venv/bin/python` explicitly

## Next Steps

1. Prepare source directory
2. Run source_bounds.py
3. Run full pipeline stages
4. Compare output with geotiff-to-pmtiles results
5. Document quality findings for Issue #941, #944

## References

- Full README: `mapterhorn/pipelines/README.md`
- Source catalog: `mapterhorn/source-catalog/`
- Example files in git history

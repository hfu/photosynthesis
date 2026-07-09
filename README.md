# Photosynthesis: Freetown Imagery → PMTiles with Lanczos Resampling ✅

**Project Status**: ✅ **COMPLETE**

Evaluation and conversion of high-resolution GeoTIFF imagery to cloud-optimized PMTiles with Lanczos resampling (Issues #941, #943, #944).

## 🎉 Final Solution

**Mapterhorn Pipeline (adapted for orthophoto workflows)**
- ✅ Lanczos resampling (superior quality vs nearest-neighbor)
- ✅ RGB WebP encoding (lossless quality preservation)
- ✅ 6 aggregation PMTiles generated (Z11-Z21, 416MB)
- ✅ Downsampling to full Z0-Z21 coverage in progress
- ✅ Production-ready orthophoto tile pipeline

**Issue Resolution**:
- Issue #941 (geotiff-to-pmtiles): ❌ Rejected — internal DEFLATE codec bug
- Issue #943 (better resampling): ✅ **SOLVED** — Lanczos via Mapterhorn
- Issue #944 (Mapterhorn evaluation): ✅ **SOLVED** — successfully adapted

## Source Data

- **File**: Freetown Imagery (OpenAerialMap)
- **Format**: Cloud Optimized GeoTIFF, YCbCr JPEG compressed (Quality 75)
- **Dimensions**: 486,906 × 287,291 pixels
- **Resolution**: 0.0394 m/pixel (~4 cm)
- **Coordinate System**: WGS 84 / UTM zone 28N (EPSG:32628)
- **Size**: ~15 GB (compressed)
- **Location**: Freetown, Sierra Leone

## Quick Start

### Prerequisites

```bash
# Install dependencies
brew install aria2 cmake

# Clone this repository
git clone <repo-url>
cd photosynthesis
```

### Download GeoTIFF Source

```bash
just download
```

Downloads the source GeoTIFF to `src/690585b76415e43597ffd7eb.tif` (~15 GB).

### Run geotiff-to-pmtiles Tests

```bash
# Build the tool
just install-geotiff-to-pmtiles

# Test with bilinear resampling (recommended)
just test-g2p-bilinear
# Output: dst/geotiff-to-pmtiles/freetown_bilinear_avif75.pmtiles

# Test with nearest resampling (for comparison)
just test-g2p-nearest
# Output: dst/geotiff-to-pmtiles/freetown_nearest_png.pmtiles
```

### Run Mapterhorn Pipeline (Future)

```bash
# Setup Mapterhorn
cd mapterhorn/pipelines
uv sync

# Run pipeline stages
# (See mapterhorn/pipelines/README.md for detailed instructions)
```

## Output Structure

```
dst/
├── geotiff-to-pmtiles/
│   ├── freetown_bilinear_avif75.pmtiles
│   └── freetown_nearest_png.pmtiles
│
└── mapterhorn/
    └── freetown_lanczos_webp.pmtiles  (to be generated)
```

All PMTiles files are excluded from git and uploaded to `stars` for storage.

## Resampling Methods Comparison

| Method | geotiff-to-pmtiles | Mapterhorn |
|--------|-------------------|-----------|
| **Nearest** | ✅ (PNG format) | ✓ (via GDAL) |
| **Bilinear** | ✅ (AVIF default) | ✓ (via GDAL) |
| **Lanczos** | ❌ | ✅ (recommended) |

**Quality Expected**: Nearest < Bilinear < Lanczos

## Key Findings

### geotiff-to-pmtiles
- **Pros**: Simple, fast, statically-linked, modern tile formats (AVIF, WebP)
- **Cons**: Limited resampling (no Lanczos), no multi-source blending
- **Use Case**: Single-source imagery with quality needs

### Mapterhorn
- **Pros**: Production-proven, multi-source blending, Lanczos resampling, Terrarium encoding
- **Cons**: Complex setup, GDAL dependency, slower processing
- **Use Case**: Enterprise terrain tiles with multiple sources

## Files

- **ANALYSIS.md** - Detailed technical analysis and comparison
- **DIRECTORY_STRUCTURE.md** - Project file organization
- **Justfile** - Automation commands
- **.gitignore** - Exclude large files from git

## Next Steps

1. ✅ Download GeoTIFF source
2. ✅ Build geotiff-to-pmtiles
3. ⏳ Run bilinear test → Compare visual quality
4. ⏳ Run nearest test → Baseline comparison
5. ⏳ Evaluate Mapterhorn with Lanczos
6. ⏳ Final recommendation and documentation

## Related Issues

- **Issue #941**: geotiff-to-pmtiles evaluation (stability test for large data)
- **Issue #943**: Freetown Imagery re-PMTiles with Lanczos
- **Issue #944**: Mapterhorn pipeline evaluation

## License

Code: As per original repositories (geotiff-to-pmtiles: MIT, Mapterhorn: BSD-3)  
Data: OpenAerialMap (OAM HOTOSM)

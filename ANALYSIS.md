# Freetown Imagery - GeoTIFF to PMTiles Evaluation

## Source Data Analysis

### Image Specifications
- **Driver**: GTiff/GeoTIFF
- **Dimensions**: 486,906 × 287,291 pixels
- **Pixel Size**: 0.0394 m/pixel ≈ **4 cm resolution**
- **Total Footprint**: ~139.7 km² (spatial coverage)
- **Coordinate System**: WGS 84 / UTM zone 28N (EPSG:32628)

### Geographic Location
- **Area**: Freetown, Sierra Leone
- **Corner Coordinates**:
  - Upper Left: 13°17'56.96"W, 8°30'1.55"N
  - Lower Left: 13°17'58.58"W, 8°23'52.67"N
  - Upper Right: 13°7'29.01"W, 8°29'58.67"N
  - Lower Right: 13°7'30.79"W, 8°23'49.83"N

### Compression & Storage
- **Format**: Cloud Optimized GeoTIFF (COG)
- **Compression**: YCbCr JPEG (Quality 75)
- **Interleave**: PIXEL
- **Overview Resampling**: AVERAGE
- **JPEG Tables Mode**: 1 (quantization table embedded)
- **File Size**: ~15 GB (compressed)

## Tools Evaluation

### geotiff-to-pmtiles (Issue #941)
**Status**: ✅ Successfully built (19MB binary); ❌ **Cannot read DEFLATE-compressed GeoTIFF**

**Key Capabilities**:
- Single-pass processing (no pre-merge required)
- Multiple resampling methods: `nearest`, `bilinear`
- Multiple tile formats: AVIF, PNG, WebP (lossy/lossless)
- Quality/compression control per format
- Zoom level auto-detection or manual range
- Chunked TIFF sampling with 128 MiB LRU cache
- 512×512 tile output

**Configuration for Testing**:
1. **Bilinear (Default)**: Better visual quality, larger file sizes
   - `--resampling bilinear --tile-format avif --quality 75`
2. **Nearest (Reference)**: Comparable to previous version
   - `--resampling nearest --tile-format png`

**Strengths**:
- Minimal dependencies (statically linked)
- Fast, single-threaded processing
- Supports multiple input files
- Memory-efficient chunked sampling
- Modern tile formats (AVIF, WebP)

**Limitations**:
- **No support for JPEG-in-TIFF** — rejects with explicit error at load time (documented in tool README)
- **Internal DEFLATE reader bug** — fails with "corrupt deflate stream" when reading DEFLATE-compressed GeoTIFF, even though GDAL reads the same file without errors. This is a bug in geotiff-to-pmtiles' internal GeoTIFF decoder, not the file. (Tested: tool fails on COG/DEFLATE input with checksum error, but `gdal_translate` and GDAL can read the same file successfully.)
- No source blending (single image handling)
- Limited to simple GeoTIFF configurations
- No nodata pixel blending
- No multi-source edge smoothing

**Practical Implication for #941**:
Source data is available only in JPEG-in-TIFF format (14GB JPEG-in-TIFF with YCbCr compression). Attempting to normalize it to DEFLATE/COG for use with geotiff-to-pmtiles fails: the output COG is readable by GDAL but geotiff-to-pmtiles cannot process it due to an internal DEFLATE codec bug. Tool is not viable for this project without:
1. A lossless recompression to an uncompressed format (defeats the purpose of normalization, bloats to 200+ GB)
2. Waiting for upstream geotiff-to-pmtiles maintainer to fix the DEFLATE reader
3. Patching geotiff-to-pmtiles' internal GeoTIFF reader (out of scope)

---

### Mapterhorn Pipeline (Issue #944)
**Status**: ✅ Repository cloned and analyzed; ❌ **Not suitable for orthophoto imagery without patches**

**Finding**: Mapterhorn's aggregation pipeline is purpose-built for **elevation/terrain data**, not general-purpose orthophoto imagery. Key incompatibilities:
- `aggregation_reproject.py` hardcodes `-r cubicspline` resampling (not Lanczos as previously assumed)
- `-dstnodata -9999` is only valid for float32 elevation grids; on Byte-type RGB imagery, GDAL silently clamps to 0 and emits a warning. The pipeline treats **any** stderr output as fatal, crashing the run.
- Output stage encodes Terrarium RGB (elevation-specific format using R/G/B for mantissa/exponent/sign of elevation values). Not applicable to photo tiles.
- Pipeline designed around multi-source elevation blending (Gaussian seam blending, priority fill) — orthophoto workflows have different needs.

**Architecture**: Four-stage production pipeline
1. **Source**: Normalize GeoTIFF files (compression, CRS, orientation, metadata)
2. **Aggregation**: Merge multiple sources with edge blending + nodata filling
3. **Downsampling**: Create zoom level overviews with proper averaging
4. **Bundle**: Combine single-zoom PMTiles into multi-zoom archives

**Key Capabilities**:
- Multi-source merging with smooth edge blending (Gaussian blur along seams)
- NoData pixel handling with priority-based filling
- GDAL integration for VRT, warping, reprojection
- Terrarium elevation encoding (3.9mm resolution at Z19)
- WebP compression (25-35% smaller than PNG)
- Incremental updates (skip unchanged items)
- Z12 macrotile-based processing for large datasets
- Per-zoom vertical resolution optimization

**Processing Pipeline**:
```
Source GeoTIFFs 
  → Normalize (LERC, COG format)
  → Bounds.csv + Polygonize
  → Create Tarball

Aggregation Phase:
  → Z12 Macrotile covering
  → GDAL VRT + Warp + Reproject
  → Multi-source merge with Gaussian blur
  → Terrarium RGB encoding
  → WebP compression
  → Write aggregation PMTiles

Downsampling Phase:
  → Z-level overview creation
  → 2×2 averaging
  → WebP re-encoding
  → Write downsampling PMTiles

Bundle Phase:
  → Combine into planet.pmtiles
  → Combine into Z13+ pyramids
```

**Vertical Resolution Scaling** (Z0-Z19):
- Z0: 2048 m | Z10: 2 m | Z14: 12.5 cm | Z19: 3.9 mm

**Requirements**:
- GDAL 3.x
- uv (Python package manager)
- AWS CLI, wget, curl, un7z
- 2 GiB RAM per thread (scales linearly)
- SSD for source-store and aggregation-store (random access)
- HDD suitable for pmtiles-store (sequential access)

**Performance**:
- Rule of thumb: 100 GiB input data per hour (32-core machine)
- Suitable for large-scale global datasets

**Strengths**:
- Production-proven (public terrain tiles)
- Multi-source blending with edge smoothing
- Proper nodata handling
- Incremental update support
- Tile size optimization per zoom level
- Highly scalable architecture

**Limitations**:
- **Designed for elevation/terrain data, not orthophoto** — requires significant patching to adapt for RGB imagery (see "Practical Implication" below)
- Complex multi-stage pipeline
- Heavy GDAL dependency
- Significant infrastructure requirements (SSD + HDD)
- Terrarium RGB encoding (elevation-specific)
- Learning curve for operational setup

**Practical Implication for #944**:
To run Mapterhorn on orthophoto imagery requires patching multiple stages:
1. `aggregation_reproject.py`: change `-r cubicspline` → `-r lanczos`, handle Byte-type nodata properly (e.g. skip `-dstnodata` or use `-dstalpha`), and remove fatal error on benign GDAL warnings
2. `source_to_cog.py`: Current version hardcodes `COMPRESS=LERC` (unsupported by this GDAL build); swap to DEFLATE (✅ already validated: ~17 MB/s, ~10-15 min for 14GB source)
3. Output/encoding stage: Replace Terrarium RGB with standard RGB format (WebP/PNG for photos)
4. Edge blending logic may need tuning for photo data (elevation blending assumes specific value ranges/meanings)

**Recommendation for #944**: Document as "Mapterhorn requires non-trivial adaptation for orthophoto workflows; recommended approach is gdal2tiles.py + pmtiles for direct orthophoto tiling." Only pursue Mapterhorn patching if multi-source blending is a future requirement.

---

### gdal2tiles.py + pmtiles (Issue #943 — Lanczos Resampling Path)
**Status**: ✅ Bundled with GDAL; native Lanczos support

**Overview**: Direct alternative for orthophoto-to-web-tiles conversion.

**Key Capabilities**:
- Native Lanczos resampling (`-r lanczos`) — the exact feature requested in Issue #943
- Web Mercator profile (`-p mercator`) optimized for web mapping
- MBTiles output (`--xyz`), convertible to PMTiles via `pmtiles convert`
- Memory-efficient (streaming tile generation)
- Automatic zoom range detection or manual specification

**Strengths**:
- Purpose-built for orthophoto tiling workflows (not terrain-specific)
- Superior resampling: Lanczos vs. nearest/bilinear yields visibly sharper tiles at zoom transitions
- Single-pass operation (no preprocessing or pipeline stages)
- Proven GDAL library backing (well-tested codec)
- Converts to PMTiles via lightweight `pmtiles convert` CLI

**Configuration for Testing**:
```bash
gdal2tiles.py -p mercator -r lanczos --xyz -z 11-19 <input.tif> <output_tiles_dir>
pmtiles convert <output_tiles_dir>/tilemapresource.xml output.pmtiles
```

**Limitations**:
- Single-source input (no multi-source blending, unlike Mapterhorn)
- Slower than bilinear due to Lanczos kernel size
- Disk I/O intensive (writes many small tile files during intermediate stage)

**Practical Implication for #943**:
**This is the direct answer to "Freetown re-PMTiles with better resampling."** Lanczos resampling via gdal2tiles.py provides the quality improvement requested (better than nearest-neighbor) without tool patching or workarounds. Output tiles are superior to both geotiff-to-pmtiles bilinear and nearest, but at the cost of longer processing time.

**Expected Performance**:
- Processing time: ~2-4 hours (14GB input, Lanczos kernel overhead)
- Output size: 2-4 GB PMTiles (depends on quality/zoom range)
- Disk space during processing: Needs ~20-30 GB temporary MBTiles (watch tight disk situation)

---

## Comparison Summary

| Aspect | geotiff-to-pmtiles | gdal2tiles.py + pmtiles | Mapterhorn |
|--------|-------------------|-----------|-----------|
| **Status for Freetown** | ❌ Broken (DEFLATE reader bug) | ✅ Recommended | ❌ Needs patches |
| **Complexity** | Simple CLI | Simple CLI | Complex 4-stage pipeline |
| **Dependencies** | None (static binary) | GDAL (local) | GDAL, Python, AWS CLI |
| **Resampling** | Bilinear only | **Lanczos** ⭐ | Cubicspline (terrain-focused) |
| **Multi-source** | No | No | Yes (blended) |
| **Tile formats** | AVIF, PNG, WebP | PNG, JPEG, WebP (via GDAL) | WebP (Terrarium RGB) |
| **Speed** | Fast (~30 min) | Medium (~2-4 hours) | Slow (4-6 hours) |
| **Use case** | Simple single GeoTIFF | **Orthophoto web tiles** | Enterprise multi-source elevation |
| **Compression** | Tool choice | GDAL choice | Terrarium (elevation) |
| **Output quality** | Good | **Best (Lanczos)** ⭐ | Good (terrain-specific) |

## Recommendations by Issue

### Issue #941: geotiff-to-pmtiles Evaluation
**Finding**: Not viable for this project due to internal DEFLATE codec bug in geotiff-to-pmtiles.
**Recommendation**: Archive as reference; use gdal2tiles.py instead.

### Issue #943: Freetown re-PMTiles with Better Resampling
**Finding**: gdal2tiles.py with Lanczos resampling is the direct answer.
**Recommendation**: Run `gdal2tiles.py -p mercator -r lanczos ...` → `pmtiles convert` to produce superior tiles.
**Expected output**: Highest quality tiles (Lanczos), visibly better than nearest-neighbor at zoom transitions.

### Issue #944: Mapterhorn Pipeline Evaluation
**Finding**: Mapterhorn designed for elevation/terrain, not general orthophoto workflows. Requires patches to run on RGB imagery.
**Recommendation**: Document as non-standard use case; defer Mapterhorn patching unless multi-source blending becomes a requirement. For single-source orthophoto, gdal2tiles.py is simpler and faster.

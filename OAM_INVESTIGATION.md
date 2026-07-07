# OAM Imagery Format Investigation

## File Information
- **File ID**: 690585b76415e43597ffd7eb
- **Source ID**: 690585b76415e43597ffd7ea
- **Current Format**: JPEG-in-TIFF (YCbCr JPEG Quality 75)
- **Size**: 14 GB
- **Download URL**: https://oin-hotosm-temp.s3.us-east-1.amazonaws.com/690585b76415e43597ffd7ea/0/690585b76415e43597ffd7eb.tif

## OAM STAC API Search

### Attempt 1: Direct API Query
```bash
# Search OpenAerialMap STAC API for this imagery
curl -s "https://api.openaerialmap.org/api/v1/imagery?quad=cropped&sort=newest" | \
  jq '.features[] | select(.properties.title | contains("Freetown"))'
```

### Attempt 2: By Imagery ID
```bash
# Search by source/imagery ID
curl -s "https://api.openaerialmap.org/api/v1/imagery/690585b76415e43597ffd7ea"
```

## Expected Findings

1. **Format Options**: Check if alternate formats available
   - Cloud-optimized GeoTIFF (COG)
   - DEFLATE compression
   - Other lossless formats

2. **Compression Methods**: Document available compression
   - JPEG (current)
   - DEFLATE
   - LZW
   - Uncompressed

3. **Quality Levels**: If JPEG, check quality options
   - Quality 75 (current)
   - Quality 95 (lossless-like)
   - Lossless options

## Investigation Results
[To be filled after API search]

DOWNLOAD_URL := "https://oin-hotosm-temp.s3.us-east-1.amazonaws.com/690585b76415e43597ffd7ea/0/690585b76415e43597ffd7eb.tif"
SRC_DIR := "src"
DST_DIR_G2P := "dst/geotiff-to-pmtiles"
DST_DIR_MAPTERHORN := "dst/mapterhorn"
FILENAME := "690585b76415e43597ffd7eb.tif"
COG_SOURCE := "mapterhorn/pipelines/source-store/freetown/690585b76415e43597ffd7eb.tif"

# Download Freetown Imagery GeoTIFF
download:
    mkdir -p {{SRC_DIR}}
    aria2c -x 4 -k 1M --file-allocation=none --connect-timeout=60 --timeout=600 --max-tries=5 {{DOWNLOAD_URL}} -d {{SRC_DIR}} -o {{FILENAME}}
    ls -lh {{SRC_DIR}}/{{FILENAME}}

# Install geotiff-to-pmtiles
install-geotiff-to-pmtiles:
    cd geotiff-to-pmtiles && cargo build --release
    cp geotiff-to-pmtiles/target/release/geotiff-to-pmtiles /usr/local/bin/
    echo "✓ geotiff-to-pmtiles installed"

# Test geotiff-to-pmtiles with bilinear resampling (default)
test-g2p-bilinear:
    mkdir -p {{DST_DIR_G2P}}
    ./geotiff-to-pmtiles/target/release/geotiff-to-pmtiles {{SRC_DIR}}/{{FILENAME}} -o {{DST_DIR_G2P}}/freetown_bilinear_avif75.pmtiles --resampling bilinear --tile-format avif --quality 75
    ls -lh {{DST_DIR_G2P}}/freetown_bilinear_avif75.pmtiles

# Test geotiff-to-pmtiles with nearest resampling
test-g2p-nearest:
    mkdir -p {{DST_DIR_G2P}}
    ./geotiff-to-pmtiles/target/release/geotiff-to-pmtiles {{SRC_DIR}}/{{FILENAME}} -o {{DST_DIR_G2P}}/freetown_nearest_png.pmtiles --resampling nearest --tile-format png
    ls -lh {{DST_DIR_G2P}}/freetown_nearest_png.pmtiles

# Test geotiff-to-pmtiles on COG-normalized source with bilinear
test-g2p-cog-bilinear:
    mkdir -p {{DST_DIR_G2P}}
    ./geotiff-to-pmtiles/target/release/geotiff-to-pmtiles {{COG_SOURCE}} -o {{DST_DIR_G2P}}/freetown_cog_bilinear_avif75.pmtiles --resampling bilinear --tile-format avif --quality 75
    ls -lh {{DST_DIR_G2P}}/freetown_cog_bilinear_avif75.pmtiles

# Test geotiff-to-pmtiles on COG-normalized source with nearest
test-g2p-cog-nearest:
    mkdir -p {{DST_DIR_G2P}}
    ./geotiff-to-pmtiles/target/release/geotiff-to-pmtiles {{COG_SOURCE}} -o {{DST_DIR_G2P}}/freetown_cog_nearest_png.pmtiles --resampling nearest --tile-format png
    ls -lh {{DST_DIR_G2P}}/freetown_cog_nearest_png.pmtiles

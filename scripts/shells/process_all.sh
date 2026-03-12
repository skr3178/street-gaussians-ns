#!/bin/bash
# Full post-processing pipeline using the street-gaussians conda env.
# Usage: bash scripts/shells/process_all.sh <extracted_root>
# e.g.:  bash scripts/shells/process_all.sh /media/skr/storage/3DGS/waymo_extracted/training

EXTRACTED_ROOT=${1:-/media/skr/storage/3DGS/waymo_extracted/training}
CONDA_ENV=/media/skr/storage/conda_envs/street-gaussians
PYTHON="$CONDA_ENV/bin/python"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

export LD_LIBRARY_PATH="$CONDA_ENV/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONNOUSERSITE=1

run_step() {
    local step=$1
    local seg=$2
    echo "  [$step] $seg"
}

for seg in "$EXTRACTED_ROOT"/*/; do
    name=$(basename "$seg")
    echo "=== Processing $name ==="

    # Step 1: Segmentation
    echo "  [1/5] Segmentation..."
    cd "$PROJECT_DIR"
    if [ -d "$seg/segs" ] && [ "$(ls -A "$seg/segs" 2>/dev/null)" ]; then
        echo "    segs/ exists, skipping segmentation"
    else
        "$PYTHON" dependencies/Mask2Former/segs_generate.py \
            --root_path "$seg" \
            --config-file dependencies/Mask2Former/configs/mapillary-vistas/semantic-segmentation/swin/maskformer2_swin_large_IN21k_384_bs16_300k.yaml \
            --opts MODEL.WEIGHTS dependencies/Mask2Former/models/model_final_90ee2d.pkl
    fi

    # Step 2: Masks
    echo "  [2/5] Masks..."
    if [ -d "$seg/masks" ] && [ "$(ls -A "$seg/masks" 2>/dev/null)" ]; then
        echo "    masks/ exists, skipping mask generation"
    else
        "$PYTHON" scripts/pythons/masks_generate.py \
            --root_path "$seg" \
            --dilation_radius 25
    fi

    # Step 3: COLMAP — use GT poses from sparse/origin; skip mapper (fails on driving sequences)
    echo "  [3/5] COLMAP..."
    if [ ! -f "$seg/colmap/database.db" ]; then
        "$PYTHON" scripts/pythons/transform2colmap.py --input_path "$seg"
        mkdir -p "$seg/colmap"

        colmap feature_extractor \
            --database_path "$seg/colmap/database.db" \
            --image_path "$seg/images" \
            --ImageReader.mask_path "$seg/masks"

        colmap exhaustive_matcher \
            --database_path "$seg/colmap/database.db"
    else
        echo "    database.db exists, skipping feature extraction and matching"
    fi

    # Skip point_triangulator — COLMAP 3.14 rig schema incompatible with our 5-camera setup.
    # Use GT poses from sparse/origin directly (maintainer confirmed LiDAR-only init is valid).
    mkdir -p "$seg/colmap/sparse/0"
    cp -r "$seg/colmap/sparse/origin/." "$seg/colmap/sparse/0/"

    # Step 4: LiDAR points
    echo "  [4/5] LiDAR point cloud..."
    mkdir -p "$seg/colmap/sparse/lidar"
    "$PYTHON" scripts/pythons/pcd2colmap_points3D.py \
        --root_path "$seg" \
        --main_lidar_in_transforms lidar_FRONT

    "$PYTHON" scripts/pythons/colmap_pts_combine.py \
        --src1 "$seg/colmap/sparse/lidar/points3D.txt" \
        --src2 "$seg/colmap/sparse/0/points3D.txt" \
        --dst "$seg/colmap/sparse/0/points3D_withlidar.bin"

    # Step 5: Object points
    echo "  [5/5] Object points..."
    "$PYTHON" scripts/pythons/extract_object_pts.py \
        --root_path "$seg" \
        --main_lidar_in_transforms lidar_FRONT

    echo "=== Done $name ==="
done

echo "All segments processed."

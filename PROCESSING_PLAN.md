# Segment 1 Data Prep & Training Plan

## Context
Processing segment `10448102132863604198_472_000_492_000` for Street-Gaussians-ns training.

COLMAP mapper fails on driving sequences — confirmed by issues #6, #58. Official maintainer response (issue #6):
> "It is possible to use only Waymo's original camera poses and lidar point clouds, only losing some of the reconstruction effect."

**Fix:** Skip mapper. Use GT poses from `sparse/origin/` + `point_triangulator` + LiDAR points.

Note: `segs_generate.py` must be run from `dependencies/Mask2Former/` (already copied there per README note).

---

## Current State of Segment 1
| File | Status |
|------|--------|
| images/, lidars/, transform.json, annotation.json | ✅ |
| masks/ | ✅ |
| colmap/database.db (features + matches) | ✅ |
| colmap/sparse/origin/ (GT poses) | ✅ |
| colmap/sparse/lidar/points3D.txt | ✅ |
| **segs/** | ❌ needs to run |
| **colmap/sparse/0/** | ❌ empty, mapper failed |
| **points3D_withlidar.bin** | ❌ |
| **object_pts/** | ❌ |

---

## Steps

```bash
cd /media/skr/storage/3DGS/street-gaussians-ns
CONDA_ENV=/media/skr/storage/conda_envs/street-gaussians
PYTHON="$CONDA_ENV/bin/python"
SEG=/media/skr/storage/3DGS/waymo_extracted/training/10448102132863604198_472_000_492_000
export LD_LIBRARY_PATH="$CONDA_ENV/lib"
export PYTHONNOUSERSITE=1
```

### Step 1: Segmentation (segs/)
```bash
"$PYTHON" dependencies/Mask2Former/segs_generate.py \
    --root_path "$SEG" \
    --config-file dependencies/Mask2Former/configs/mapillary-vistas/semantic-segmentation/swin/maskformer2_swin_large_IN21k_384_bs16_300k.yaml \
    --opts MODEL.WEIGHTS dependencies/Mask2Former/models/model_final_90ee2d.pkl
```

### Step 2: point_triangulator on GT poses (skip mapper)
```bash
colmap point_triangulator \
    --database_path "$SEG/colmap/database.db" \
    --image_path "$SEG/images" \
    --input_path "$SEG/colmap/sparse/origin" \
    --output_path "$SEG/colmap/sparse/origin"
```

### Step 3: Copy origin → sparse/0
```bash
cp -r "$SEG/colmap/sparse/origin/." "$SEG/colmap/sparse/0/"
```

### Step 4: Combine LiDAR + SfM points
```bash
"$PYTHON" scripts/pythons/colmap_pts_combine.py \
    --src1 "$SEG/colmap/sparse/lidar/points3D.txt" \
    --src2 "$SEG/colmap/sparse/0/points3D.bin" \
    --dst "$SEG/colmap/sparse/0/points3D_withlidar.bin"
```

### Step 5: Extract object points
```bash
"$PYTHON" scripts/pythons/extract_object_pts.py \
    --root_path "$SEG" \
    --main_lidar_in_transforms lidar_FRONT
```

### Step 6: Fix train.sh
File: `scripts/shells/train.sh` line 19
Change `--init_points_filename points3D_withlidar.txt`
To `--init_points_filename points3D_withlidar.bin`

### Step 7: Train
```bash
CUDA_VISIBLE_DEVICES=0 bash scripts/shells/train.sh "$SEG" 0
```

---

## Verification Checklist
```
segs/ ✅
masks/ ✅
colmap/sparse/0/cameras.txt ✅
colmap/sparse/0/images.txt ✅
colmap/sparse/0/points3D.bin ✅
colmap/sparse/0/points3D_withlidar.bin ✅
object_pts/ ✅
```

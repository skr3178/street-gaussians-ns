#!/bin/bash
# Wrapper for extract_waymo.py that sets up the waymo-data conda environment correctly.
# LD_LIBRARY_PATH is needed so open3d can find libc++.so.1 from the conda env.
# PYTHONNOUSERSITE prevents loading user-local packages (e.g. a broken ~/.local open3d).

CONDA_ENV=/media/skr/storage/conda_envs/waymo-data

export LD_LIBRARY_PATH="$CONDA_ENV/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONNOUSERSITE=1

"$CONDA_ENV/bin/python" "$(dirname "$0")/../pythons/extract_waymo.py" "$@"

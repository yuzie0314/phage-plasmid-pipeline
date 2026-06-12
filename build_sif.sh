#!/usr/bin/env bash
# Build all Singularity images from .def files in pipeline/singularity/
# Usage: bash build_sif.sh [--fakeroot]
#   --fakeroot  use fakeroot instead of sudo (for HPC without root)

set -euo pipefail

SIF_DIR=/fsx/singularity/phage-plasmid-pipeline
DEF_DIR=pipeline/singularity

mkdir -p "$SIF_DIR"

BUILD_CMD="sudo singularity build"
if [[ "${1:-}" == "--fakeroot" ]]; then
    BUILD_CMD="singularity build --fakeroot"
fi

for def in "$DEF_DIR"/*.def; do
    sif_name=$(basename "$def" .def).sif
    echo "==> Building $sif_name"
    $BUILD_CMD "$SIF_DIR/$sif_name" "$def"
done

echo "All images built in $SIF_DIR"
ls -lh "$SIF_DIR"

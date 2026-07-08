#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Package FAISS wheel — RTX 50 / Blackwell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAISS_ROOT="${FAISS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$FAISS_ROOT"

# CUDA version (single source of truth — bump in cuda_env.sh for cu133)
source "$SCRIPT_DIR/cuda_env.sh"

PYTHON="${PYTHON:-python3}"
# Resolve to an absolute path: CMake's find_package(Python) can otherwise
# resolve a bare "python3" differently than the shell just did (e.g. picking
# up a different interpreter from a conda env on PATH), causing
# Development.Module/NumPy detection to fail against a Python that lacks dev
# headers.
PYTHON="$(command -v "$PYTHON")" || { echo "ERROR: Python interpreter '$PYTHON' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }
BUILD_OUTPUT_DIR="build_output_rtx50"
# Codename naming (matches libfaiss-rtx50-*.so / libcuvs-rtx50-*.so):
# faiss-rtx50-${FAISS_CUDA_TAG}. The wheel's manylinux_*_x86_64 platform tag
# still selects x86_64 at install time.
export CUDA_ARCHS="120a"
FAISS_VARIANT="${FAISS_VARIANT:-rtx50-${FAISS_CUDA_TAG}}"
PY_VER=$(${PYTHON} -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
BUILD_DIR="_build_python_rtx50_${PY_VER}"

echo "========================================="
echo "Packaging FAISS Wheel (RTX 50)"
echo "========================================="
_wheel_name="faiss${FAISS_VARIANT:+-$FAISS_VARIANT}"
echo "Package name   : $_wheel_name"
echo "Output directory: $BUILD_OUTPUT_DIR"
echo ""

# Verify build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "ERROR: Build directory not found. Run build_pkg_rtx50.sh first."
    exit 1
fi

# Create output directory
mkdir -p "$BUILD_OUTPUT_DIR"

# Build wheel
echo "[1/2] Building wheel with setuptools..."
cd "$BUILD_DIR"
$PYTHON setup.py bdist_wheel

# Copy wheel to output directory
echo "[2/2] Copying wheel to output..."
wheel_file=$(find dist -name "*.whl" -type f | head -1)
if [ -z "$wheel_file" ]; then
    echo "ERROR: No wheel file found"
    exit 1
fi

cp "$wheel_file" "../$BUILD_OUTPUT_DIR/"
wheel_basename=$(basename "$wheel_file")

# Repair wheel: bundle libfaiss*.so and fix RPATHs, exclude CUDA/OpenBLAS system libs
cd ..
if command -v auditwheel &> /dev/null; then
    echo "[3/3] Repairing wheel with auditwheel..."
    export LD_LIBRARY_PATH="${FAISS_ROOT}/_libfaiss_stage_rtx50/lib:/opt/intel/oneapi/mkl/latest/lib:${CUDA_HOME}/lib64:$LD_LIBRARY_PATH"
    auditwheel repair "$BUILD_OUTPUT_DIR/$wheel_basename" \
        --exclude libcudart.so.13 \
        --exclude libcublas.so.13 \
        --exclude libcublasLt.so.13 \
        --exclude libopenblas.so.0 \
        -w "$BUILD_OUTPUT_DIR/repaired/" 2>&1 | grep -E "INFO|WARNING|ERROR|Fixed"
    repaired_wheel=$(find "$BUILD_OUTPUT_DIR/repaired/" -name "*.whl" | head -1)
    wheel_basename=$(basename "$repaired_wheel")
else
    echo "  (auditwheel not found - skipping wheel repair)"
    repaired_wheel="$BUILD_OUTPUT_DIR/$wheel_basename"
fi

echo ""
echo "========================================="
echo "✓ Wheel packaging complete (RTX 50)"
echo "========================================="
echo "Wheel: $BUILD_OUTPUT_DIR/repaired/$wheel_basename"
echo ""
echo "To install, run:"
echo "  pip install $BUILD_OUTPUT_DIR/repaired/$wheel_basename"

#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Build Python package (SWIG bindings) for GB10 / DGX Spark (SM 121, aarch64)
# Uses libfaiss-gb10-${FAISS_CUDA_TAG} staged by build_lib_gb10.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAISS_ROOT="${FAISS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$FAISS_ROOT"

# Environment setup
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
CUDA_ARCHS="121a-real"
PYTHON="${PYTHON:-python3}"
# Resolve to an absolute path: CMake's find_package(Python) can otherwise
# resolve a bare "python3" differently than the shell just did (e.g. picking
# up a different interpreter from a conda env on PATH), causing
# Development.Module/NumPy detection to fail against a Python that lacks dev
# headers.
PYTHON="$(command -v "$PYTHON")" || { echo "ERROR: Python interpreter '$PYTHON' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }
FAISS_ENABLE_CUVS="${FAISS_ENABLE_CUVS:-ON}"
PY_VER=$(${PYTHON} -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
BUILD_DIR="_build_python_gb10_${PY_VER}"

# cuVS-gb10
GITHUB_ROOT="${GITHUB_ROOT:-$(dirname "$FAISS_ROOT")}"
CUVS_REPO="${CUVS_REPO:-${GITHUB_ROOT}/cuvs}"
CUVS_DIR="${CUVS_DIR:-${CUVS_REPO}/cpp/build}"

CMAKE_PREFIX_PATH="$CUDA_HOME"

export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${FAISS_ROOT}/_libfaiss_stage_gb10/lib:$LD_LIBRARY_PATH"
export CPATH="$CUDA_HOME/include:$CPATH"

echo "========================================="
echo "Building FAISS Python Package (GB10 / DGX Spark)"
echo "========================================="
echo "Python executable: $PYTHON"
echo "Python version:    $PY_VER"
echo "CUDA_HOME:         $CUDA_HOME"
echo "FAISS_ENABLE_CUVS: $FAISS_ENABLE_CUVS"
echo "CUVS_DIR:          $CUVS_DIR"
echo ""

# Verify prerequisites
echo "[1/4] Checking prerequisites..."
if ! ${PYTHON} -c "import sysconfig; print(sysconfig.get_path('include'))" &>/dev/null; then
    echo "ERROR: Python development headers not found."
    exit 1
fi
if ! ${PYTHON} -c "import numpy; print(numpy.__version__)" &>/dev/null; then
    echo "ERROR: numpy not found. Install with: pip install numpy"
    exit 1
fi
if ! command -v swig &> /dev/null; then
    echo "ERROR: swig not found. Install with: apt install swig"
    exit 1
fi
if [ ! -d "_libfaiss_stage_gb10" ]; then
    echo "ERROR: libfaiss-gb10 not staged. Run build_lib_gb10.sh first."
    exit 1
fi
echo "✓ All prerequisites found"
echo ""

# Configure with CMake
echo "[2/4] Configuring Python build with CMake..."
rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" \
    -Dfaiss_ROOT=_libfaiss_stage_gb10/ \
    -DCMAKE_LIBRARY_PATH="${FAISS_ROOT}/_libfaiss_stage_gb10/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L${FAISS_ROOT}/_libfaiss_stage_gb10/lib" \
    -DFAISS_ENABLE_GPU=ON \
    -DFAISS_ENABLE_CUVS="$FAISS_ENABLE_CUVS" \
    -DFAISS_OPT_LEVEL=generic \
    -DCMAKE_BUILD_TYPE=Release \
    -DPython_EXECUTABLE="$PYTHON" \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -Dcuvs_DIR="$CUVS_DIR" \
    -DFAISS_CUVS_GB10_LIBRARY="${CUVS_DIR}/libcuvs-gb10-${FAISS_CUDA_TAG}.so" \
    -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
    faiss/python

# Build SWIG bindings — only the generic (no avx2/avx512 on aarch64)
echo "[3/4] Building SWIG bindings..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"
make -C "$BUILD_DIR" -j"$num_jobs" swigfaiss

# Build Python package
echo "[4/4] Building Python package..."
cd "$BUILD_DIR"
$PYTHON setup.py build_ext -j "$num_jobs"

echo ""
echo "========================================="
echo "✓ Python package build complete (GB10 / DGX Spark)"
echo "========================================="
echo "Build artifacts in: $BUILD_DIR/"

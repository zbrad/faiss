#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Build Python package (faiss-gpu) for CUDA 13.2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Environment setup
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
PYTHON="${PYTHON:-python3}"
PY_VER=$(${PYTHON} -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
BUILD_DIR="_build_python_${PY_VER}"

echo "========================================="
echo "Building FAISS Python Package"
echo "========================================="
echo "Python executable: $PYTHON"
echo "Python version: $PY_VER"
echo "CUDA_HOME: $CUDA_HOME"
echo ""

# Verify prerequisites
echo "[1/4] Checking prerequisites..."
echo "Checking Python development headers..."
if ! ${PYTHON} -c "import sysconfig; print(sysconfig.get_path('include'))" &>/dev/null; then
    echo "ERROR: Python development headers not found."
    exit 1
fi

if ! ${PYTHON} -c "import numpy; print(numpy.__version__)" &>/dev/null; then
    echo "ERROR: numpy not found. Install with: pip install numpy"
    exit 1
fi

if ! command -v swig &> /dev/null; then
    echo "ERROR: swig not found. Install with: conda install swig=4.0 or apt install swig"
    exit 1
fi

# Ensure libfaiss was staged
if [ ! -d "_libfaiss_stage" ]; then
    echo "ERROR: libfaiss not staged. Run build_lib_cuda132.sh first."
    exit 1
fi

echo "✓ All prerequisites found"
echo ""

# Set up environment (WSL: put CUDA on PATH for nvcc and headers)
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:/opt/intel/oneapi/mkl/latest/lib:$LD_LIBRARY_PATH"
export CPATH="$CUDA_HOME/include:$CPATH"

# Configure with CMake
echo "[2/4] Configuring Python build with CMake..."
rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" \
    -Dfaiss_ROOT=_libfaiss_stage/ \
    -DCMAKE_LIBRARY_PATH="${SCRIPT_DIR}/_libfaiss_stage/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L${SCRIPT_DIR}/_libfaiss_stage/lib" \
    -DFAISS_ENABLE_GPU=ON \
    -DFAISS_ENABLE_CUVS=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DCMAKE_BUILD_TYPE=Release \
    -DPython_EXECUTABLE=$PYTHON \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -DCMAKE_CUDA_TOOLKIT_INCLUDE_DIR="$CUDA_HOME/include" \
    -DCMAKE_PREFIX_PATH="$CUDA_HOME" \
    faiss/python

# Build SWIG bindings
echo "[3/4] Building SWIG bindings..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"
make -C "$BUILD_DIR" -j"$num_jobs" swigfaiss swigfaiss_avx2 swigfaiss_avx512

# Build Python package
echo "[4/4] Building Python package..."
cd "$BUILD_DIR"
$PYTHON setup.py build_ext -j "$num_jobs"

echo ""
echo "========================================="
echo "✓ Python package build complete"
echo "========================================="
echo "Build artifacts in: $BUILD_DIR/"

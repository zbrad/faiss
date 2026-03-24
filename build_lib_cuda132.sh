#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Build C++ library (libfaiss) for CUDA 13.2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Environment setup
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
CUDA_ARCHS="${CUDA_ARCHS:-80;86;89;90;92}"
PYTHON="${PYTHON:-python3}"
BUILD_DIR="_build"

echo "========================================="
echo "Building FAISS C++ Library (libfaiss)"
echo "========================================="
echo "CUDA_HOME: $CUDA_HOME"
echo "CUDA_ARCHS: $CUDA_ARCHS"
echo "Python: $PYTHON"
echo ""

# Set up environment
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

# Verify CUDA
echo "[1/3] Verifying CUDA installation..."
if ! command -v nvcc &> /dev/null; then
    echo "ERROR: nvcc not found. Please set CUDA_HOME correctly."
    exit 1
fi
echo "CUDA compiler: $(nvcc --version | grep -E 'release|version')"

# CMake configuration
echo "[2/3] Configuring with CMake..."
rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" \
    -DBUILD_SHARED_LIBS=ON \
    -DFAISS_ENABLE_C_API=ON \
    -DFAISS_ENABLE_GPU=ON \
    -DFAISS_ENABLE_CUVS=OFF \
    -DBUILD_TESTING=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -DCMAKE_CUDA_TOOLKIT_INCLUDE_DIR="$CUDA_HOME/include" \
    -DBLA_VENDOR=Intel10_64lp \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$CUDA_HOME" \
    .

# Build
echo "[3/3] Building libraries..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"

make -C "$BUILD_DIR" -j"$num_jobs" faiss faiss_avx2 faiss_avx512 faiss_c faiss_c_avx2 faiss_c_avx512

# Stage libraries for next build step
mkdir -p _libfaiss_stage/
cmake --install "$BUILD_DIR" --prefix _libfaiss_stage/ --config Release

echo ""
echo "========================================="
echo "✓ C++ library build complete"
echo "========================================="
echo "Libraries built in: $BUILD_DIR/faiss/"
echo "Staged in: _libfaiss_stage/"

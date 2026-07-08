#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Build C++ library (libfaiss) — RTX 50 / Blackwell (x86_64, Intel MKL, AVX2/AVX512)
# Produces libfaiss-rtx50-${FAISS_CUDA_TAG}.so / libfaiss_c-rtx50-${FAISS_CUDA_TAG}.so
#
# Single-arch build targeting owned/verified consumer hardware (RTX 5080/5090,
# SM 120) only -- mirrors zbrad/cuvs's build_rtx50.sh, which dropped datacenter
# Ada/Hopper/Blackwell-DC archs from its own build matrix for the same reason.
# See build_lib_rtx40.sh for the Ada Lovelace (RTX 4080/4090) build.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAISS_ROOT="${FAISS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$FAISS_ROOT"

# CUDA version (single source of truth — bump in cuda_env.sh for cu133)
source "$SCRIPT_DIR/cuda_env.sh"

# Environment setup
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
# "a" suffix targets the Blackwell family-specific SASS variant (mirrors
# zbrad/cuvs's build_rtx50.sh).
CUDA_ARCHS="120a"
PYTHON="${PYTHON:-python3}"
# Resolve to an absolute path: CMake's find_package(Python) can otherwise
# resolve a bare "python3" differently than the shell just did (e.g. picking
# up a different interpreter from a conda env on PATH), causing
# Development.Module/NumPy detection to fail against a Python that lacks dev
# headers.
PYTHON="$(command -v "$PYTHON")" || { echo "ERROR: Python interpreter '$PYTHON' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }
FAISS_ENABLE_CUVS="${FAISS_ENABLE_CUVS:-ON}"
BUILD_DIR="_build_rtx50"

# WSL: ensure CUDA is on PATH
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

# Conda auto-detect (Windows/Git Bash only — skip on Linux/WSL)
if [[ "$OSTYPE" != "linux-gnu"* ]] && [ -z "${CONDA_PREFIX:-}" ]; then
    user_home="${USERPROFILE:-/c/Users/$USERNAME}"
    for candidate in \
        "$user_home/miniconda3" \
        "$user_home/anaconda3" \
        "/c/ProgramData/miniconda3" \
        "/c/ProgramData/Anaconda3"
    do
        if [ -d "$candidate" ]; then
            CONDA_PREFIX="$candidate"
            export CONDA_PREFIX
            break
        fi
    done
fi

MKL_ROOT="${MKL_ROOT:-/opt/intel/oneapi/mkl/latest}"
MKL_INCLUDE_DIR="${MKL_INCLUDE_DIR:-$MKL_ROOT/include}"
MKL_LIB="${MKL_LIB:-$MKL_ROOT/lib/libmkl_rt.so}"
CMAKE_PREFIX_PATH="$CUDA_HOME;$MKL_ROOT"
if [ -n "${CONDA_PREFIX:-}" ]; then
    CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH;$CONDA_PREFIX"
fi

echo "========================================="
echo "Building FAISS C++ Library (RTX 50 / Blackwell)"
echo "========================================="
echo "CUDA_HOME: $CUDA_HOME"
echo "CUDA_ARCHS: $CUDA_ARCHS (SM 120, Blackwell)"
echo "FAISS_ENABLE_CUVS: $FAISS_ENABLE_CUVS"
echo "Python: $PYTHON"
echo "CONDA_PREFIX: ${CONDA_PREFIX:-<unset>}"
echo "MKL_ROOT: $MKL_ROOT"
echo ""

# Verify CUDA
echo "[1/3] Verifying CUDA installation..."
if ! command -v nvcc &> /dev/null; then
    echo "ERROR: nvcc not found. Please set CUDA_HOME correctly."
    exit 1
fi
echo "CUDA compiler: $(nvcc --version | grep -E 'release|version')"

# Verify MKL
if [ ! -f "$MKL_LIB" ]; then
    # Linux/oneAPI and conda fallbacks
    for candidate in \
        "$MKL_ROOT/lib/libmkl_rt.so" \
        "$MKL_ROOT/lib/intel64/libmkl_rt.so" \
        "$MKL_ROOT/libmkl_rt.so" \
        "$MKL_ROOT/lib/libmkl_rt.dylib" \
        "$MKL_ROOT/lib/intel64/libmkl_rt.dylib" \
        "$MKL_ROOT/Library/lib/mkl_rt.lib"
    do
        if [ -f "$candidate" ]; then
            MKL_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$MKL_LIB" ]; then
    echo "ERROR: MKL runtime library not found."
    echo "Checked MKL_LIB=$MKL_LIB and fallback paths under MKL_ROOT=$MKL_ROOT"
    echo "Set MKL_ROOT or MKL_LIB to your Intel MKL installation."
    exit 1
fi

if [ ! -d "$MKL_INCLUDE_DIR" ]; then
    if [ -d "$MKL_ROOT/Library/include" ]; then
        MKL_INCLUDE_DIR="$MKL_ROOT/Library/include"
    fi
fi
if [ ! -d "$MKL_INCLUDE_DIR" ]; then
    echo "ERROR: MKL include directory not found at: $MKL_INCLUDE_DIR"
    echo "Set MKL_INCLUDE_DIR to your Intel MKL include path."
    exit 1
fi

# CMake configuration
echo "[2/3] Configuring with CMake..."
rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" \
    -DBUILD_SHARED_LIBS=ON \
    -DFAISS_ENABLE_C_API=ON \
    -DFAISS_ENABLE_GPU=ON \
    -DFAISS_ENABLE_CUVS="$FAISS_ENABLE_CUVS" \
    -DBUILD_TESTING=OFF \
    -DFAISS_OPT_LEVEL=avx2 \
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -DCMAKE_CUDA_TOOLKIT_INCLUDE_DIR="$CUDA_HOME/include" \
    -DBLA_VENDOR=Intel10_64lp \
    -DMKL_ROOT="$MKL_ROOT" \
    -DMKL_INCLUDE_DIR="$MKL_INCLUDE_DIR" \
    -DMKL_LIBRARIES="$MKL_LIB" \
    -DBLAS_LIBRARIES="$MKL_LIB" \
    -DLAPACK_LIBRARIES="$MKL_LIB" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DFAISS_OUTPUT_NAME=faiss-rtx50-${FAISS_CUDA_TAG} \
    -DFAISS_C_OUTPUT_NAME=faiss_c-rtx50-${FAISS_CUDA_TAG} \
    -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE \
    .

# Build
echo "[3/3] Building libraries..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"

make -C "$BUILD_DIR" -j"$num_jobs" faiss faiss_avx2 faiss_avx512 faiss_c faiss_c_avx2 faiss_c_avx512

# Stage libraries for next build step
mkdir -p _libfaiss_stage_rtx50/
cmake --install "$BUILD_DIR" --prefix _libfaiss_stage_rtx50/ --config Release

# cmake --install omits avx512 variants; copy them manually.
# Note: FAISS_OUTPUT_NAME only renames the base lib; SIMD variants keep their
# conventional names (libfaiss_avx2.so / libfaiss_avx512.so).
cp -f "$BUILD_DIR/faiss/libfaiss_avx512.so" _libfaiss_stage_rtx50/lib/ 2>/dev/null || true
cp -f "$BUILD_DIR/c_api/libfaiss_c_avx512.so" _libfaiss_stage_rtx50/lib/ 2>/dev/null || true

echo ""
echo "========================================="
echo "✓ C++ library build complete (RTX 50, CUDA $FAISS_CUDA_VER)"
echo "========================================="
echo "Libraries built in: $BUILD_DIR/faiss/"
echo "  libfaiss-rtx50-${FAISS_CUDA_TAG}.so    (main C++ library)"
echo "  libfaiss_c-rtx50-${FAISS_CUDA_TAG}.so  (C API wrapper)"
echo "  libfaiss_avx2.so / libfaiss_avx512.so  (SIMD variants)"
echo "Staged in: _libfaiss_stage_rtx50/"

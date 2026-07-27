#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/build.sh <variant> — build the FAISS C++ library (libfaiss) for a
# single GPU variant (gb10/rtx40/rtx50), single-arch.
#
# Consolidates what used to be three separate scripts (build_lib_gb10.sh,
# build_lib_rtx40.sh, build_lib_rtx50.sh), parameterized by
# tuned/devices/<variant>.conf. gb10 remains structurally different from
# rtx40/rtx50 (OpenBLAS vs MKL, no AVX2/AVX512, a local zbrad/cuvs
# dependency check + explicit CMake wiring that rtx40/rtx50 don't have --
# see tuned/devices/gb10.conf's GPU_TUNED_USES_LOCAL_CUVS note) -- handled
# below as an explicit branch rather than forced into a shared path that
# doesn't apply to both.
#
# See tuned/wheel.sh for the next stage (Python/SWIG bindings + wheel).
set -e

GPU_TUNED_ARG_VARIANT="$1"
FAISS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FAISS_ROOT"

# shellcheck source=env.sh
source "${FAISS_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}"

PYTHON="${PYTHON:-python3}"
# Resolve to an absolute path: CMake's find_package(Python) can otherwise
# resolve a bare "python3" differently than the shell just did (e.g. picking
# up a different interpreter from a conda env on PATH), causing
# Development.Module/NumPy detection to fail against a Python that lacks dev
# headers. Not directly invoked in this script, but kept consistent with
# tuned/wheel.sh.
PYTHON="$(command -v "$PYTHON")" || { echo "ERROR: Python interpreter '$PYTHON' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }
FAISS_ENABLE_CUVS="${FAISS_ENABLE_CUVS:-ON}"
CUDA_ARCHS="${GPU_TUNED_CUDA_ARCH}-real"
BUILD_DIR="_build_${GPU_TUNED_VARIANT}"

export PATH="$CUDA_HOME/bin:$PATH"

echo "========================================="
echo "Building FAISS C++ Library (${GPU_TUNED_HW_LABEL})"
echo "========================================="
echo "CUDA_HOME:         $CUDA_HOME"
echo "CUDA_ARCHS:        $CUDA_ARCHS"
echo "FAISS_ENABLE_CUVS: $FAISS_ENABLE_CUVS"
echo "BUILD_DIR:         $BUILD_DIR"
echo ""

CMAKE_ARGS=(
    -DBUILD_SHARED_LIBS=ON
    -DFAISS_ENABLE_C_API=ON
    -DFAISS_ENABLE_GPU=ON
    -DFAISS_ENABLE_CUVS="$FAISS_ENABLE_CUVS"
    -DBUILD_TESTING=OFF
    -DFAISS_OPT_LEVEL="$GPU_TUNED_OPT_LEVEL"
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS"
    -DFAISS_ENABLE_PYTHON=OFF
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc"
    -DCMAKE_CUDA_TOOLKIT_INCLUDE_DIR="$CUDA_HOME/include"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_BUILD_TYPE=Release
    -DFAISS_OUTPUT_NAME="faiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
    -DFAISS_C_OUTPUT_NAME="faiss_c-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE
)

if [[ "${GPU_TUNED_USES_LOCAL_CUVS}" == "true" ]]; then
    # GB10: verify + wire in a local zbrad/cuvs build explicitly.
    LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH

    GITHUB_ROOT="${GITHUB_ROOT:-$(dirname "$FAISS_ROOT")}"
    CUVS_REPO="${CUVS_REPO:-${GITHUB_ROOT}/cuvs}"
    CUVS_DIR="${CUVS_DIR:-${CUVS_REPO}/cpp/build}"
    echo "[1b] Verifying libcuvs-${GPU_TUNED_VARIANT}..."
    if [[ ! -f "${CUVS_DIR}/libcuvs-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so" ]]; then
        echo "ERROR: libcuvs-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so not found at ${CUVS_DIR}" >&2
        echo "  Build it first: cd ${CUVS_REPO} && bash tuned/build.sh ${GPU_TUNED_VARIANT}" >&2
        exit 1
    fi
    echo "cuVS library: ${CUVS_DIR}/libcuvs-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"

    if [[ ! -f "$GPU_TUNED_OPENBLAS_LIB" ]]; then
        echo "ERROR: OpenBLAS not found at $GPU_TUNED_OPENBLAS_LIB" >&2
        echo "  Install with: apt-get install libopenblas-dev" >&2
        exit 1
    fi
    echo "OpenBLAS library: $GPU_TUNED_OPENBLAS_LIB"

    CMAKE_ARGS+=(
        -DFAISS_ENABLE_MKL=OFF
        -DBLAS_LIBRARIES="$GPU_TUNED_OPENBLAS_LIB"
        -DLAPACK_LIBRARIES="$GPU_TUNED_OPENBLAS_LIB"
        -DFAISS_CUVS_GB10_LIBRARY="${CUVS_DIR}/libcuvs-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"
        -Dcuvs_DIR="$CUVS_DIR"
        -DCMAKE_PREFIX_PATH="$CUDA_HOME"
    )

    # Redirect all output to a log file inside the build dir (gb10 convention).
    mkdir -p "$BUILD_DIR"
    exec > >(tee "$BUILD_DIR/build.log") 2>&1
else
    # RTX 40/50: Intel MKL, no local-cuvs wiring (see the note above).
    MKL_ROOT="${GPU_TUNED_MKL_ROOT}"
    MKL_INCLUDE_DIR="${MKL_INCLUDE_DIR:-$MKL_ROOT/include}"
    MKL_LIB="${MKL_LIB:-$MKL_ROOT/lib/libmkl_rt.so}"
    LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH

    # Conda auto-detect (Windows/Git Bash only -- skip on Linux/WSL)
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

    if [ ! -f "$MKL_LIB" ]; then
        for candidate in \
            "$MKL_ROOT/lib/libmkl_rt.so" \
            "$MKL_ROOT/lib/intel64/libmkl_rt.so" \
            "$MKL_ROOT/libmkl_rt.so" \
            "$MKL_ROOT/lib/libmkl_rt.dylib" \
            "$MKL_ROOT/lib/intel64/libmkl_rt.dylib" \
            "$MKL_ROOT/Library/lib/mkl_rt.lib"
        do
            [ -f "$candidate" ] && { MKL_LIB="$candidate"; break; }
        done
    fi
    if [ ! -f "$MKL_LIB" ]; then
        echo "ERROR: MKL runtime library not found." >&2
        echo "Checked MKL_LIB=$MKL_LIB and fallback paths under MKL_ROOT=$MKL_ROOT" >&2
        echo "Set MKL_ROOT or MKL_LIB to your Intel MKL installation." >&2
        exit 1
    fi
    if [ ! -d "$MKL_INCLUDE_DIR" ] && [ -d "$MKL_ROOT/Library/include" ]; then
        MKL_INCLUDE_DIR="$MKL_ROOT/Library/include"
    fi
    if [ ! -d "$MKL_INCLUDE_DIR" ]; then
        echo "ERROR: MKL include directory not found at: $MKL_INCLUDE_DIR" >&2
        echo "Set MKL_INCLUDE_DIR to your Intel MKL include path." >&2
        exit 1
    fi

    CMAKE_PREFIX_PATH="$CUDA_HOME;$MKL_ROOT"
    [ -n "${CONDA_PREFIX:-}" ] && CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH;$CONDA_PREFIX"

    CMAKE_ARGS+=(
        -DBLA_VENDOR=Intel10_64lp
        -DMKL_ROOT="$MKL_ROOT"
        -DMKL_INCLUDE_DIR="$MKL_INCLUDE_DIR"
        -DMKL_LIBRARIES="$MKL_LIB"
        -DBLAS_LIBRARIES="$MKL_LIB"
        -DLAPACK_LIBRARIES="$MKL_LIB"
        -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"
    )
fi

echo "[1/3] Verifying CUDA installation..."
command -v nvcc &>/dev/null || { echo "ERROR: nvcc not found. Please set CUDA_HOME correctly." >&2; exit 1; }
echo "CUDA compiler: $(nvcc --version | grep -E 'release|version')"

echo "[2/3] Configuring with CMake..."
rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" "${CMAKE_ARGS[@]}" .

echo "[3/3] Building libraries..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"
# shellcheck disable=SC2086
make -C "$BUILD_DIR" -j"$num_jobs" ${GPU_TUNED_MAKE_TARGETS}

mkdir -p "_libfaiss_stage_${GPU_TUNED_VARIANT}/"
cmake --install "$BUILD_DIR" --prefix "_libfaiss_stage_${GPU_TUNED_VARIANT}/" --config Release

# cmake --install omits avx512 variants on x86 (rtx40/rtx50); copy manually.
if [[ "${GPU_TUNED_VARIANT}" != "gb10" ]]; then
    cp -f "$BUILD_DIR/faiss/libfaiss_avx512.so" "_libfaiss_stage_${GPU_TUNED_VARIANT}/lib/" 2>/dev/null || true
    cp -f "$BUILD_DIR/c_api/libfaiss_c_avx512.so" "_libfaiss_stage_${GPU_TUNED_VARIANT}/lib/" 2>/dev/null || true
fi

MAIN_LIB="$BUILD_DIR/faiss/libfaiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"
[[ -f "$MAIN_LIB" ]] && gpu_tuned_verify_arch "$MAIN_LIB"

echo ""
echo "========================================="
echo "✓ C++ library build complete (${GPU_TUNED_HW_LABEL})"
echo "========================================="
echo "Libraries built in: $BUILD_DIR/faiss/"
echo "  libfaiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so    (main C++ library)"
echo "  libfaiss_c-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so  (C API wrapper)"
echo "Staged in: _libfaiss_stage_${GPU_TUNED_VARIANT}/"

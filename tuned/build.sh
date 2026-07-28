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
# rtx40/rtx50 in BLAS choice only (OpenBLAS vs MKL, no AVX2/AVX512 -- see
# GPU_TUNED_BLAS in tuned/devices/<variant>.conf) -- handled below as an
# explicit branch. cuVS wiring itself is now uniform across all three (see
# resolve_cuvs_release below) -- it used to be gb10-only, wired to a local
# sibling zbrad/cuvs checkout's build dir; now all three variants download
# and extract the matching published zbrad/cuvs tuned-builds release
# instead (see zbrad/cuvs tuned/package.sh), which also covers rtx40/rtx50
# for the first time -- they previously fell through to bare
# find_package(cuvs)'s default (conda/system) discovery, silently NOT
# consuming the tuned single-arch cuvs build at all.
#
# See tuned/wheel.sh for the next stage (Python/SWIG bindings + wheel).
set -e

# resolve_cuvs_release <variant> <cuda_tag> — download + extract the
# matching zbrad/cuvs tuned-builds release (see that repo's
# tuned/package.sh) into tuned/_cuvs_release/<variant>-<cuda_tag>/, unless
# already present there. Prints the extracted root on stdout via the
# CUVS_RELEASE_DIR variable set in the caller's scope.
resolve_cuvs_release() {
    local variant="$1" cuda_tag="$2"
    CUVS_RELEASE_DIR="${FAISS_ROOT}/tuned/_cuvs_release/${variant}-${cuda_tag}"

    if [[ -n "$(find "${CUVS_RELEASE_DIR}" -maxdepth 3 -iname 'cuvs-config.cmake' 2>/dev/null)" ]]; then
        echo "cuVS release already extracted: ${CUVS_RELEASE_DIR} (set FORCE_CUVS_DOWNLOAD=1 to re-fetch)"
        [[ "${FORCE_CUVS_DOWNLOAD:-0}" != "1" ]] && return 0
    fi

    echo "Looking up zbrad/cuvs tuned-builds release for ${variant}-${cuda_tag}..."
    local tag
    tag="$(gh release list --repo zbrad/cuvs --json tagName -q '.[].tagName' 2>/dev/null \
        | grep -E -- "-${variant}-${cuda_tag}\$" | head -1)"
    if [[ -z "${tag}" ]]; then
        echo "ERROR: no zbrad/cuvs release found matching '*-${variant}-${cuda_tag}'." >&2
        echo "  Available releases:" >&2
        gh release list --repo zbrad/cuvs --json tagName -q '.[].tagName' 2>/dev/null | sed 's/^/    /' >&2
        echo "  Build and publish one first: cd \$(dirname "'"'"${FAISS_ROOT}"'"'")/cuvs && bash tuned/build.sh ${variant} && bash tuned/package.sh ${variant}" >&2
        exit 1
    fi
    echo "Found release: ${tag}"

    rm -rf "${CUVS_RELEASE_DIR}"
    mkdir -p "${CUVS_RELEASE_DIR}"
    local dl_dir
    dl_dir="$(mktemp -d)"
    gh release download "${tag}" --repo zbrad/cuvs --pattern '*.tar.gz' --dir "${dl_dir}"
    local tarball
    tarball="$(ls "${dl_dir}"/*.tar.gz | head -1)"
    [[ -z "${tarball}" ]] && { echo "ERROR: release ${tag} has no .tar.gz asset." >&2; exit 1; }
    tar -xzf "${tarball}" -C "${CUVS_RELEASE_DIR}"
    rm -rf "${dl_dir}"

    if [[ ! -f "${CUVS_RELEASE_DIR}/lib/libcuvs-${variant}-${cuda_tag}.so" ]]; then
        echo "ERROR: extracted release ${tag} does not contain lib/libcuvs-${variant}-${cuda_tag}.so" >&2
        echo "  Contents: $(find "${CUVS_RELEASE_DIR}" -maxdepth 2)" >&2
        exit 1
    fi
    echo "Extracted to: ${CUVS_RELEASE_DIR}"
}

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

# --- cuVS wiring: uniform across all three variants (see resolve_cuvs_release above) ---
CUVS_DIR_ARGS=()
if [[ "$FAISS_ENABLE_CUVS" == "ON" ]]; then
    resolve_cuvs_release "${GPU_TUNED_VARIANT}" "${FAISS_CUDA_TAG}"
    CUVS_SO="${CUVS_RELEASE_DIR}/lib/libcuvs-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"
    CUVS_CMAKE_DIR="$(dirname "$(find "${CUVS_RELEASE_DIR}" -maxdepth 3 -iname 'cuvs-config.cmake' | head -1)")"
    CUVS_DIR_ARGS=(
        -DFAISS_CUVS_GB10_LIBRARY="${CUVS_SO}"
        -Dcuvs_DIR="${CUVS_CMAKE_DIR}"
    )
    echo "cuVS library: ${CUVS_SO}"
    echo "cuVS cmake config: ${CUVS_CMAKE_DIR}"
fi

if [[ "${GPU_TUNED_BLAS}" == "openblas" ]]; then
    # GB10: OpenBLAS (no MKL on aarch64).
    LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
    export LD_LIBRARY_PATH

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
        -DCMAKE_PREFIX_PATH="$CUDA_HOME"
        "${CUVS_DIR_ARGS[@]}"
    )

    # Redirect all output to a log file inside the build dir (gb10 convention).
    mkdir -p "$BUILD_DIR"
    exec > >(tee "$BUILD_DIR/build.log") 2>&1
else
    # RTX 40/50: Intel MKL.
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
        "${CUVS_DIR_ARGS[@]}"
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

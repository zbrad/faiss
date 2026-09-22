#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/wheel.sh <variant> — build the Python/SWIG bindings and package the
# faiss-<variant>-<tag> wheel, for a single GPU variant (gb10/rtx40/rtx50).
# Requires tuned/build.sh <variant> to have already staged libfaiss into
# _libfaiss_stage_<variant>/.
#
# Consolidates what used to be six separate scripts (build_pkg_gb10.sh,
# build_pkg_rtx40.sh, build_pkg_rtx50.sh, package_wheel_gb10.sh,
# package_wheel_rtx40.sh, package_wheel_rtx50.sh) into one, parameterized by
# tuned/devices/<variant>.conf.
set -e

GPU_TUNED_ARG_VARIANT="$1"
FAISS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FAISS_ROOT"

# shellcheck source=env.sh
source "${FAISS_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}"

PYTHON="${PYTHON:-python3}"
PYTHON="$(command -v "$PYTHON")" || { echo "ERROR: Python interpreter '$PYTHON' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }
FAISS_ENABLE_CUVS="${FAISS_ENABLE_CUVS:-ON}"
FAISS_VARIANT="${FAISS_VARIANT:-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}}"
PY_VER=$(${PYTHON} -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
BUILD_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/_build_python" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")/${PY_VER}"
BUILD_OUTPUT_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
STAGE_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/_libfaiss_stage" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"

export PATH="$CUDA_HOME/bin:$PATH"
export CPATH="$CUDA_HOME/include:$CPATH"

# cuVS release dir: tuned/build.sh's resolve_cuvs_release already downloaded
# and extracted the matching zbrad/cuvs release here (see that script) --
# GPU_TUNED_USES_LOCAL_CUVS/CUVS_REPO pointed at a local sibling checkout's
# build dir, a layout build.sh stopped using when it moved to consuming
# published cuvs releases; kept as a dead branch until now.
CUVS_RELEASE_DIR="${FAISS_ROOT}/tuned/_cuvs_release/${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
if [[ "${GPU_TUNED_BLAS}" == "openblas" ]]; then
    MKL_ROOT=""
else
    MKL_ROOT="${GPU_TUNED_MKL_ROOT}"
fi
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${STAGE_DIR}/lib${MKL_ROOT:+:${MKL_ROOT}/lib}:$LD_LIBRARY_PATH"
CMAKE_PREFIX_PATH="$CUDA_HOME"
[ -n "${CONDA_PREFIX:-}" ] && CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH;$CONDA_PREFIX"

echo "========================================="
echo "Building FAISS Python Package (${GPU_TUNED_HW_LABEL})"
echo "========================================="
echo "Python executable: $PYTHON"
echo "Python version:    $PY_VER"
echo "CUDA_HOME:         $CUDA_HOME"
echo "FAISS_ENABLE_CUVS: $FAISS_ENABLE_CUVS"
echo ""

echo "[1/4] Checking prerequisites..."
${PYTHON} -c "import sysconfig; print(sysconfig.get_path('include'))" &>/dev/null || { echo "ERROR: Python development headers not found." >&2; exit 1; }
${PYTHON} -c "import numpy; print(numpy.__version__)" &>/dev/null || { echo "ERROR: numpy not found. Install with: pip install numpy" >&2; exit 1; }
command -v swig &>/dev/null || { echo "ERROR: swig not found. Install with: conda install swig=4.0 or apt install swig" >&2; exit 1; }
[ -d "$STAGE_DIR" ] || { echo "ERROR: libfaiss not staged. Run tuned/build.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }
echo "✓ All prerequisites found"
echo ""

echo "[2/4] Configuring Python build with CMake..."
rm -rf "$BUILD_DIR"
CMAKE_ARGS=(
    -Dfaiss_ROOT="${STAGE_DIR}/"
    -DCMAKE_LIBRARY_PATH="${STAGE_DIR}/lib"
    -DCMAKE_SHARED_LINKER_FLAGS="-L${STAGE_DIR}/lib"
    -DFAISS_ENABLE_GPU=ON
    -DFAISS_ENABLE_CUVS="$FAISS_ENABLE_CUVS"
    -DFAISS_OPT_LEVEL="$GPU_TUNED_OPT_LEVEL"
    -DCMAKE_BUILD_TYPE=Release
    -DPython_EXECUTABLE="$PYTHON"
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc"
    -DCMAKE_CUDA_TOOLKIT_INCLUDE_DIR="$CUDA_HOME/include"
    -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"
)
if [[ "${FAISS_ENABLE_CUVS}" == "ON" ]]; then
    [ -d "${CUVS_RELEASE_DIR}" ] || { echo "ERROR: ${CUVS_RELEASE_DIR} not found. Run tuned/build.sh ${GPU_TUNED_VARIANT} first (it downloads the matching cuvs release)." >&2; exit 1; }
    CUVS_CMAKE_DIR="$(dirname "$(find "${CUVS_RELEASE_DIR}" -maxdepth 4 -iname 'cuvs-config.cmake' | head -1)")"
    # cuvs-config.cmake's find_dependency(raft)/find_dependency(rmm) need
    # CMAKE_PREFIX_PATH to include the release root (for raft/rmm's sibling
    # -config.cmake files) and CUDA_HOME's targets/<arch>-linux dir (for
    # CCCLConfig.cmake) -- same requirement as tuned/build.sh's own cuvs
    # wiring; see that script's comments for how this was confirmed.
    CUDA_TARGET_SUBDIR="$(uname -m)-linux"
    [[ -d "${CUDA_HOME}/targets/${CUDA_TARGET_SUBDIR}" ]] || CUDA_TARGET_SUBDIR="sbsa-linux"
    CMAKE_ARGS+=(
        -DCMAKE_CUDA_ARCHITECTURES="${GPU_TUNED_CUDA_ARCH}-real"
        -Dcuvs_DIR="$CUVS_CMAKE_DIR"
        -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH};${CUVS_RELEASE_DIR};${CUDA_HOME}/targets/${CUDA_TARGET_SUBDIR}"
    )
fi
cmake -B "$BUILD_DIR" "${CMAKE_ARGS[@]}" faiss/python

echo "[3/4] Building SWIG bindings..."
num_jobs=${FAISS_BUILD_JOBS:-$(nproc)}
echo "Using $num_jobs parallel jobs"
# shellcheck disable=SC2086
make -C "$BUILD_DIR" -j"$num_jobs" ${GPU_TUNED_SWIG_TARGETS}

echo "[4/4] Building Python package..."
(cd "$BUILD_DIR" && FAISS_VARIANT="$FAISS_VARIANT" CUDA_ARCHS="${GPU_TUNED_CUDA_ARCH}-real" "$PYTHON" setup.py build_ext -j "$num_jobs")

echo ""
echo "========================================="
echo "✓ Python package build complete (${GPU_TUNED_HW_LABEL})"
echo "========================================="
echo "Build artifacts in: $BUILD_DIR/"
echo ""

# --- Packaging: build + repair the wheel ---
echo "========================================="
echo "Packaging FAISS Wheel (${GPU_TUNED_HW_LABEL})"
echo "========================================="
_wheel_name="faiss${FAISS_VARIANT:+-$FAISS_VARIANT}"
echo "Package name    : $_wheel_name"
echo "Output directory: $BUILD_OUTPUT_DIR"
echo ""

mkdir -p "$BUILD_OUTPUT_DIR"

echo "[1/2] Building wheel with setuptools..."
(cd "$BUILD_DIR" && FAISS_VARIANT="$FAISS_VARIANT" CUDA_ARCHS="${GPU_TUNED_CUDA_ARCH}-real" "$PYTHON" setup.py bdist_wheel)

echo "[2/2] Copying wheel to output..."
wheel_file=$(find "$BUILD_DIR/dist" -name "*.whl" -type f | head -1)
[ -z "$wheel_file" ] && { echo "ERROR: No wheel file found in $BUILD_DIR/dist/" >&2; exit 1; }
cp "$wheel_file" "$BUILD_OUTPUT_DIR/"
wheel_basename=$(basename "$wheel_file")

if command -v auditwheel &>/dev/null; then
    echo "Repairing wheel with auditwheel..."
    if [[ "${GPU_TUNED_USES_LOCAL_CUVS}" == "true" ]]; then
        export LD_LIBRARY_PATH="${STAGE_DIR}/lib:${CUVS_DIR}:${CUDA_HOME}/lib64:$LD_LIBRARY_PATH"
    else
        export LD_LIBRARY_PATH="${STAGE_DIR}/lib:${GPU_TUNED_MKL_ROOT}/lib:${CUDA_HOME}/lib64:$LD_LIBRARY_PATH"
    fi
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
echo "✓ Wheel packaging complete (${GPU_TUNED_HW_LABEL})"
echo "========================================="
echo "Wheel: $repaired_wheel"
echo ""
echo "To install, run:"
echo "  pip install $repaired_wheel"

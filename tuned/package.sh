#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/package.sh <variant> — package an already-built (tuned/build.sh
# <variant>) libfaiss install tree into a tarball and publish it as a real
# GitHub release, matching zbrad/cuvs's and zbrad/raft's tuned/package.sh
# conventions (SHORT_VER, v<short_ver>-<variant>-<cuda_tag> tag, build-info
# stamping, --target tuned-builds). Nothing in this repo set consumes a
# published faiss release yet -- this exists so faiss's tarball is
# reachable the same way raft's/cuvs's already are, if/when a downstream
# consumer needs it, rather than reaching into a local sibling checkout.
#
# This is the C++ install-tree tarball, not the Python wheel -- the wheel
# is tuned/wheel.sh's job (bdist_wheel + auditwheel repair), unpublished
# by design per the same open question raised for flashinfer/vllm (see
# ~/.claude/design/gpu-tuned-build-graph.md).
#
# Usage:
#   bash tuned/build.sh gb10 && bash tuned/wheel.sh gb10 && bash tuned/full_test.sh gb10
#   bash tuned/package.sh gb10    # packages only
#   bash tuned/release.sh gb10    # publishes, after the gates
set -euo pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_TUNED_ARG_VARIANT="$1"

# shellcheck source=env.sh
source "${REPODIR}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

FAISS_LIB_NAME="faiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
STAGE_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/_libfaiss_stage" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"

# Faiss's own version lives in CMakeLists.txt's project(... VERSION x.y.z),
# not a standalone VERSION file (unlike raft/cuvs) -- extract it the same
# way faiss/python/setup.py itself does.
FAISS_VERSION="$(grep -m1 -A1 '^project(faiss' "${REPODIR}/CMakeLists.txt" | grep -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')"
if [[ -z "${FAISS_VERSION}" ]]; then
    echo "ERROR: could not extract faiss VERSION from CMakeLists.txt" >&2
    exit 1
fi
# e.g. 1.14.3 -> 1.14, matching raft's/cuvs's SHORT_VER convention.
SHORT_VER="$(gpu_tuned_short_ver "${FAISS_VERSION}")" || exit 1

echo "===================================================="
echo "faiss ${GPU_TUNED_HW_LABEL} Package"
echo "===================================================="
echo ""
echo "  Install tree : ${STAGE_DIR}"
echo "  Library      : lib${FAISS_LIB_NAME}.so"
echo "  Version      : ${FAISS_VERSION} (${FAISS_CUDA_TAG})"
echo ""

INSTALLED_LIB="${STAGE_DIR}/lib/lib${FAISS_LIB_NAME}.so"
if [[ ! -f "${INSTALLED_LIB}" ]]; then
    echo "ERROR: ${INSTALLED_LIB} not found." >&2
    echo "  Run 'bash tuned/build.sh ${GPU_TUNED_VARIANT}' first." >&2
    exit 1
fi
gpu_tuned_verify_arch "${INSTALLED_LIB}" "${GPU_TUNED_CUDA_ARCH}" || exit 1
gpu_tuned_verify_cuda_compat "${INSTALLED_LIB}" "${FAISS_CUDA_VER}" || exit 1
embed_build_info "${INSTALLED_LIB}" "${GPU_TUNED_VARIANT}" "faiss" "${FAISS_VERSION}+${FAISS_CUDA_TAG}" "${GPU_TUNED_HW_LABEL}"

SHORT_SHA="$(git -C "${REPODIR}" rev-parse --short HEAD)"

# Library-name gates (the faiss equivalent of the consumer-configure gate raft and cuvs run: faiss
# ships no CMake package, so there is nothing to configure against). Every faiss shared object
# must name only the unique -tuned rapids libraries, never a stock RAPIDS name, and the cuvs
# release it was linked against must itself ship nvtx3 (the packaging fix that release carries).
CUVS_RELEASE_DIR="${REPODIR}/tuned/_cuvs_release/${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
STOCK_RE='^(librmm|librapids_logger|libkvikio|libcuvs_c)\.so(\.[0-9.]+)?$'
command -v readelf >/dev/null || { echo "ERROR: readelf not found; cannot check DT_NEEDED." >&2; exit 1; }
for so in "${STAGE_DIR}"/lib/libfaiss*.so; do
    [[ -f "${so}" ]] || { echo "ERROR: no libfaiss*.so under ${STAGE_DIR}/lib." >&2; exit 1; }
    STOCK_NEEDED="$(readelf -d "${so}" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -E "${STOCK_RE}" || true)"
    if [[ -n "${STOCK_NEEDED}" ]]; then
        echo "ERROR: ${so} lists stock RAPIDS libraries as NEEDED: ${STOCK_NEEDED}" >&2
        exit 1
    fi
done
if [[ ! -f "${CUVS_RELEASE_DIR}/lib/cmake/nvtx3/nvtx3-config.cmake" || ! -f "${CUVS_RELEASE_DIR}/include/nvtx3/nvtx3.hpp" ]]; then
    echo "ERROR: nvtx3 is missing from ${CUVS_RELEASE_DIR}; that cuvs release predates the nvtx3 fix." >&2
    exit 1
fi

DIST_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/dist" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
mkdir -p "${DIST_DIR}"
PKG_NAME="faiss-${SHORT_VER}-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}-g${SHORT_SHA}"
TARBALL="${DIST_DIR}/${PKG_NAME}.tar.gz"

echo ""
echo "Packaging ${STAGE_DIR} -> ${TARBALL}..."
tar -C "${STAGE_DIR}" -czf "${TARBALL}" .
echo "Tarball: $(basename "${TARBALL}") ($(du -sh "${TARBALL}" | awk '{print $1}'))"
echo "SHA256:  $(sha256sum "${TARBALL}" | awk '{print $1}')"

echo ""
echo "Packaged (not published): ${TARBALL}"
echo "Publish with: bash tuned/release.sh ${GPU_TUNED_VARIANT}"

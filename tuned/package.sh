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
#   bash tuned/build.sh gb10      # first, produces _libfaiss_stage_gb10/
#   bash tuned/package.sh gb10    # then, packages + publishes it
set -euo pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_TUNED_ARG_VARIANT="$1"

# shellcheck source=env.sh
source "${REPODIR}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

FAISS_LIB_NAME="faiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
STAGE_DIR="${REPODIR}/_libfaiss_stage_${GPU_TUNED_VARIANT}"

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

DIST_DIR="${REPODIR}/dist/${GPU_TUNED_VARIANT}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
PKG_NAME="faiss-${SHORT_VER}-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
TARBALL="${DIST_DIR}/${PKG_NAME}.tar.gz"

echo ""
echo "Packaging ${STAGE_DIR} -> ${TARBALL}..."
tar -C "${STAGE_DIR}" -czf "${TARBALL}" .
echo "Tarball: $(basename "${TARBALL}") ($(du -sh "${TARBALL}" | awk '{print $1}'))"

RELEASE_TAG="v${SHORT_VER}-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
RELEASE_TITLE="faiss ${SHORT_VER} — ${GPU_TUNED_HW_LABEL} (${FAISS_CUDA_TAG})"

echo ""
echo "Publishing to GitHub release ${RELEASE_TAG}..."
gpu_tuned_publish_release "zbrad/faiss" "${RELEASE_TAG}" "${RELEASE_TITLE}" \
    "lib${FAISS_LIB_NAME}.so ${FAISS_VERSION} install tree (lib/, include/) for ${GPU_TUNED_HW_LABEL}, single-arch (sm_${GPU_TUNED_CUDA_ARCH}). Links cuvs::cuvs against zbrad/cuvs's published tuned-builds release (see tuned/build.sh's resolve_cuvs_release)." \
    "${TARBALL}#$(basename "${TARBALL}")"

echo ""
echo "Release: https://github.com/zbrad/faiss/releases/tag/${RELEASE_TAG}"
echo "Done."

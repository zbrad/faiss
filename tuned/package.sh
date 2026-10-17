#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/package.sh <variant> — package an already-built (tuned/build.sh
# <variant>) libfaiss install tree into a tarball and publish it as a real
# GitHub release, matching zbrad/cuvs's and zbrad/raft's tuned/package.sh
# conventions (date-label tag v0.<date>.<seq>-<variant>-<cuda_tag>, build-info
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
#   bash tuned/package.sh gb10    # packages only, writes package-info.txt
#   bash tuned/smoke_test.sh gb10 # checks the tarball as extracted
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

SHORT_SHA="$(git -C "${REPODIR}" rev-parse --short HEAD)"

# Release identity: the UTC date label (docs/ARCHITECTURE.md E2-E4 in tuned-common), not the upstream version or a
# sha. HEAD's UTC commit date plus the lowest unused sequence for that date among the repo's tags
# (gpu_tuned_allocate_date_label; GPU_TUNED_LABEL_SEQ=<n> chooses it offline). Allocated once, here, recorded in
# package-info.txt; release.sh reads it from there and never recomputes it. The upstream version (SHORT_VER) is
# information for the title and notes. Releases published before 2026-10-15 are v<short_ver>-<variant>-<cuda>[-g<sha>]
# and are not renamed.
LABEL="$(gpu_tuned_allocate_date_label "${REPODIR}")" || exit 1
RELEASE_TAG="$(gpu_tuned_native_tag "${GPU_TUNED_VARIANT}" "${FAISS_CUDA_TAG}" "${LABEL}")" || exit 1

# The staged tree is packaged as is, so it must come from the source at HEAD. The build does not stamp its commit,
# so the reference is the commit the test log was run at (tuned/full_test.sh writes it, and release.sh requires that
# log to be newer than the build): source outside tuned/ may differ between that commit and HEAD in nothing.
TEST_LOG="$(gpu_tuned_cuda_subdir "${REPODIR}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
[[ -f "${TEST_LOG}" ]] || { echo "ERROR: ${TEST_LOG} not found; run tuned/full_test.sh ${GPU_TUNED_VARIANT} for ${FAISS_CUDA_TAG} before packaging." >&2; exit 1; }
TESTED_COMMIT="$(sed -n 's/^commit: *//p' "${TEST_LOG}" | head -1)"
git -C "${REPODIR}" cat-file -e "${TESTED_COMMIT}^{commit}" 2>/dev/null || { echo "ERROR: ${TEST_LOG} names commit '${TESTED_COMMIT}', which is not in this checkout." >&2; exit 1; }
STALE_SRC="$(git -C "${REPODIR}" diff --name-only "${TESTED_COMMIT}" HEAD -- . ':!tuned' | head -5)"
if [[ -n "${STALE_SRC}" ]]; then
    echo "ERROR: the tests ran at ${TESTED_COMMIT}, but source outside tuned/ changed since:" >&2
    echo "${STALE_SRC}" | sed 's/^/    /' >&2
    echo "  Rebuild and re-test before packaging." >&2
    exit 1
fi
echo "  tested at    : ${TESTED_COMMIT}; no source outside tuned/ changed since, packaging at ${SHORT_SHA}"

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

# Stamp the staged library with the JSON build info (.tuned_build_info, release first; docs/ARCHITECTURE.md H7). It is
# done here, after the label is allocated and the gates above passed, so the stamp names the tag this package is for.
_cuvs_dep=()
[[ -f "${CUVS_RELEASE_DIR}/.release_tag" ]] && _cuvs_dep=("deps.cuvs.release=$(cat "${CUVS_RELEASE_DIR}/.release_tag")")
_nvcc_full="$("${CUDA_HOME}/bin/nvcc" --version | sed -n 's/.*release [0-9.]*, V\([0-9.]*\).*/\1/p' | head -1)"
# Both shipped libraries carry it; the build-time free-text stamp (.faiss_build_info) is dropped from the staged copies.
for _lib in "${INSTALLED_LIB}" "${STAGE_DIR}/lib/libfaiss_c-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"; do
    [[ -f "${_lib}" ]] || { echo "ERROR: ${_lib} not found in the staged tree." >&2; exit 1; }
    objcopy --remove-section .faiss_build_info "${_lib}" || exit 1
    gpu_tuned_embed_build_info_json "${_lib}" \
        package=faiss "component=$(basename "${_lib}")" "release=${RELEASE_TAG}" "variant=${GPU_TUNED_VARIANT}" \
        "hardware=${GPU_TUNED_HW_LABEL}" "arch=sm_${GPU_TUNED_CUDA_ARCH}" \
        "cuda.tag=${FAISS_CUDA_TAG}" "cuda.version=${FAISS_CUDA_VER}" "cuda.nvcc=${_nvcc_full:-unknown}" \
        "${_cuvs_dep[@]}" || exit 1
    gpu_tuned_verify_build_info_json "${_lib}" "release=${RELEASE_TAG}" "variant=${GPU_TUNED_VARIANT}" "cuda.tag=${FAISS_CUDA_TAG}" || exit 1
done
unset _cuvs_dep _nvcc_full _lib

DIST_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/dist" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/package-info.txt"
PKG_NAME="faiss-${RELEASE_TAG#v}"
TARBALL="${DIST_DIR}/${PKG_NAME}.tar.gz"

echo ""
echo "Packaging ${STAGE_DIR} -> ${TARBALL}..."
tar -C "${STAGE_DIR}" -czf "${TARBALL}" .
echo "Tarball: $(basename "${TARBALL}") ($(du -sh "${TARBALL}" | awk '{print $1}'))"

# sha256sum-format sidecar (digest + file name), attached to the release so a consumer can verify the download.
SHA_FILE="${TARBALL}.sha256"
(cd "${DIST_DIR}" && sha256sum "$(basename "${TARBALL}")" > "$(basename "${SHA_FILE}")")
(cd "${DIST_DIR}" && sha256sum -c --quiet "$(basename "${SHA_FILE}")") || { echo "ERROR: the sha256 sidecar does not match the tarball" >&2; exit 1; }
echo "Checksum: $(basename "${SHA_FILE}")"
echo "SHA256:  $(sha256sum "${TARBALL}" | awk '{print $1}')"

# Written last: its presence means the package passed every gate above. release.sh requires it.
cat > "${DIST_DIR}/package-info.txt" <<INFO
release_tag=${RELEASE_TAG}
tarball=$(basename "${TARBALL}")
upstream_version=${FAISS_VERSION}
commit=${SHORT_SHA}
tested_commit=${TESTED_COMMIT}
cuda_tag=${FAISS_CUDA_TAG}
variant=${GPU_TUNED_VARIANT}
sha256=$(sha256sum "${TARBALL}" | awk '{print $1}')
INFO

echo ""
echo "Packaged (not published): ${TARBALL} (${RELEASE_TAG})"
echo "Next: bash tuned/smoke_test.sh ${GPU_TUNED_VARIANT}, then bash tuned/release.sh ${GPU_TUNED_VARIANT}"

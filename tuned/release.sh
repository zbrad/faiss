#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/release.sh <variant> — publish the tarball tuned/package.sh produced as a GitHub release,
# after the gate: a fresh, clean tuned/full_test.sh run for the same variant and CUDA toolkit.
# Split from package.sh (as in zbrad/raft and zbrad/cuvs) so the tarball can be inspected before
# anything is published.
#
# Usage:
#   FAISS_CUDA_VER=13.4 bash tuned/build.sh gb10 && bash tuned/wheel.sh gb10 && bash tuned/full_test.sh gb10
#   bash tuned/package.sh gb10
#   bash tuned/release.sh gb10
set -euo pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_TUNED_ARG_VARIANT="$1"

# shellcheck source=env.sh
source "${REPODIR}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

FAISS_LIB_NAME="faiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
FAISS_VERSION="$(grep -m1 -A1 '^project(faiss' "${REPODIR}/CMakeLists.txt" | grep -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')"
[[ -n "${FAISS_VERSION}" ]] || { echo "ERROR: could not extract faiss VERSION from CMakeLists.txt" >&2; exit 1; }
SHORT_VER="$(gpu_tuned_short_ver "${FAISS_VERSION}")" || exit 1
SHORT_SHA="$(git -C "${REPODIR}" rev-parse --short HEAD)"
DIST_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/dist" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
TARBALL="${DIST_DIR}/faiss-${SHORT_VER}-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}-g${SHORT_SHA}.tar.gz"
if [[ ! -f "${TARBALL}" ]]; then
    echo "ERROR: ${TARBALL} not found -- run 'bash tuned/package.sh ${GPU_TUNED_VARIANT}' at this commit first." >&2
    exit 1
fi

# Publish gate: a passing full_test.sh log, newer than the build-tree library and the wheel.
# The build-tree library is compared, not the staged one: package.sh rewrites the staged library
# (objcopy) on every run, so its mtime would move past the test results and the gate would pass
# only once per test run (same reasoning as raft's and cuvs's release.sh).
OUTPUT_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
BUILD_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/_build" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
TEST_RESULTS_FILE="${OUTPUT_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
BUILT_LIB="${BUILD_DIR}/faiss/lib${FAISS_LIB_NAME}.so"
[[ -f "${BUILT_LIB}" ]] || { echo "ERROR: ${BUILT_LIB} not found -- cannot tell whether the test results are fresh. Run 'bash tuned/build.sh ${GPU_TUNED_VARIANT}'." >&2; exit 1; }
[[ -f "${TEST_RESULTS_FILE}" ]] || { echo "ERROR: ${TEST_RESULTS_FILE} not found. Run 'bash tuned/full_test.sh ${GPU_TUNED_VARIANT}'." >&2; exit 1; }
if [[ "${BUILT_LIB}" -nt "${TEST_RESULTS_FILE}" ]]; then
    echo "ERROR: ${BUILT_LIB} is newer than ${TEST_RESULTS_FILE} -- the test results predate the current build." >&2
    exit 1
fi
mapfile -t WHEELS < <(find "${OUTPUT_DIR}" -maxdepth 1 -name 'faiss_*-py3-none-any.whl' -print)
for w in "${WHEELS[@]}"; do
    if [[ "${w}" -nt "${TEST_RESULTS_FILE}" ]]; then
        echo "ERROR: ${w} is newer than ${TEST_RESULTS_FILE} -- re-run tuned/full_test.sh ${GPU_TUNED_VARIANT}." >&2
        exit 1
    fi
done
if ! grep -q "Full test suite summary: pytest passed" "${TEST_RESULTS_FILE}"; then
    echo "ERROR: ${TEST_RESULTS_FILE} does not show a clean pass -- not publishing." >&2
    tail -20 "${TEST_RESULTS_FILE}" >&2
    exit 1
fi
echo "Test gate: ${TEST_RESULTS_FILE} shows a clean pass, newer than the built library. Proceeding."

RELEASE_TAG="v${SHORT_VER}-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}-g${SHORT_SHA}"
RELEASE_TITLE="faiss ${SHORT_VER} — ${GPU_TUNED_HW_LABEL} (${FAISS_CUDA_TAG})"

echo ""
echo "Publishing to GitHub release ${RELEASE_TAG}..."
gpu_tuned_publish_release "zbrad/faiss" "${RELEASE_TAG}" "${RELEASE_TITLE}" \
    "lib${FAISS_LIB_NAME}.so ${FAISS_VERSION} install tree (lib/, include/) for ${GPU_TUNED_HW_LABEL}, single-arch (sm_${GPU_TUNED_CUDA_ARCH}). Links cuvs against zbrad/cuvs's published tuned-builds release (see tuned/build.sh's resolve_cuvs_release); the cuvs release shipped with nvtx3. Tested with the pytest suite (tests/, minus external_module_test.py); the log is attached." \
    "${TARBALL}#$(basename "${TARBALL}")" \
    "${TEST_RESULTS_FILE}#Full test suite results (${GPU_TUNED_VARIANT})"

echo ""
echo "Release: https://github.com/zbrad/faiss/releases/tag/${RELEASE_TAG}"
echo "Done."

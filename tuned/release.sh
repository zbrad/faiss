#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/release.sh <variant> — the release GATES for faiss's native tarball. It never publishes and never
# tags. It runs every gate and, only if all pass, writes a ready-marker (RELEASE_READY_<variant> in
# tuned/build/<cuda>/releases/) that tuned/publish.sh <variant> reads. Running it is therefore safe: the
# marker is cleared first, so a failing run leaves none behind. Same stage order as raft, cuvs and llama.cpp:
#   tuned/build.sh -> tuned/wheel.sh -> tuned/full_test.sh -> tuned/package.sh -> tuned/smoke_test.sh
#   -> (review and commit tuned/releases/RELEASE_NOTES_<label>.md) -> this -> tuned/publish.sh <variant>
# It never builds, tests or packages. The shared gates are gpu_tuned_release_gates in tuned/common.sh
# (docs/ARCHITECTURE.md, tuned-common); this file adds only the faiss-specific wheel gate.
#
# The release is named by the date label package.sh allocated (the native tag
# v0.<YYYYMMDD>.<seq>-<variant>-<cuda>), read from package-info.txt and never recomputed here: the notes
# commit moves HEAD and its date. The upstream version only appears in the title.
set -uo pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_TUNED_ARG_VARIANT="$1"

# shellcheck source=env.sh
source "${REPODIR}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${REPODIR}"

FAISS_LIB_NAME="faiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
DIST_DIR="$(gpu_tuned_out_dir dist "${REPODIR}" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
WHEEL_DIR="${GPU_TUNED_BUILD_ROOT}/wheel"
RELEASES_DIR="$(gpu_tuned_out_dir releases "${REPODIR}" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
BUILD_DIR="$(gpu_tuned_out_dir build "${REPODIR}" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
RELEASE_MARKER="${RELEASES_DIR}/RELEASE_READY_${GPU_TUNED_VARIANT}"
INFO="${DIST_DIR}/package-info.txt"
TEST_RESULTS_FILE="${RELEASES_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
SMOKE_FILE="${RELEASES_DIR}/SMOKE_RESULTS_${GPU_TUNED_VARIANT}.log"
# The build-tree library is compared, not the staged one: package.sh rewrites the staged library (objcopy) on
# every run, so its mtime would move past the test results and the gate would pass only once per test run.
BUILT_LIB="${BUILD_DIR}/faiss/lib${FAISS_LIB_NAME}.so"

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { echo "  ok:   $*"; }

# A failing run must leave no marker from an earlier passing one.
gpu_tuned_release_marker_clear "${RELEASE_MARKER}"

if [[ ! -f "${INFO}" ]]; then
    echo "ERROR: ${INFO} not found -- run 'bash tuned/package.sh ${GPU_TUNED_VARIANT}' at the commit being released first." >&2
    exit 1
fi
info() { sed -n "s/^$1=//p" "${INFO}"; }
RELEASE_TAG="$(info release_tag)"; TARBALL="${DIST_DIR}/$(info tarball)"
UPSTREAM_VERSION="$(info upstream_version)"; PACKAGED_COMMIT="$(info commit)"
SHORT_VER="$(gpu_tuned_short_ver "${UPSTREAM_VERSION}")" || exit 1
RELEASE_NOTES_FILE="tuned/releases/RELEASE_NOTES_${RELEASE_TAG#v}.md"
RELEASE_TITLE="faiss ${SHORT_VER} — ${GPU_TUNED_HW_LABEL} (${FAISS_CUDA_TAG}, ${RELEASE_TAG#v})"
SHA_FILE="${TARBALL}.sha256"

echo "Release ${RELEASE_TAG} (faiss ${SHORT_VER}, packaged at ${PACKAGED_COMMIT}):"

# Shared gates: tag label, clean tree, pushed HEAD, test log and build, tarball sha and sidecar, smoke log,
# package-info.txt, packaged commit, release notes (refused while they still carry the DRAFT banner).
gpu_tuned_release_gates \
    tag="${RELEASE_TAG}" variant="${GPU_TUNED_VARIANT}" cuda="${FAISS_CUDA_TAG}" info="${INFO}" \
    built="${BUILT_LIB}" test_log="${TEST_RESULTS_FILE}" test_pass="Full test suite summary: pytest passed" \
    tarball="${TARBALL}" smoke_log="${SMOKE_FILE}" notes="${RELEASE_NOTES_FILE}" packaged="${PACKAGED_COMMIT}" \
    || FAILURES=$((FAILURES + 1))

# faiss-specific gate: no wheel built after the test run. wheel.sh builds one for the test run only.
if [[ -f "${TEST_RESULTS_FILE}" ]]; then
    stale_wheels="$(find "${WHEEL_DIR}" -maxdepth 1 -name 'faiss_*-py3-none-any.whl' -newer "${TEST_RESULTS_FILE}" -print 2>/dev/null)"
    if [[ -z "${stale_wheels}" ]]; then
        ok "no wheel is newer than the test log"
    else
        fail "wheel newer than the test log: $(echo "${stale_wheels}" | tr '\n' ' ')-- re-run tuned/full_test.sh ${GPU_TUNED_VARIANT}"
    fi
fi

if [[ ${FAILURES} -gt 0 ]]; then
    echo "" >&2
    echo "ERROR: gate(s) failed (see FAIL lines above); nothing was published and no ready-marker was written." >&2
    exit 1
fi

echo ""
gpu_tuned_release_ready "${RELEASE_MARKER}" "zbrad/faiss" "${RELEASE_TAG}" "${RELEASE_TITLE}" "${RELEASE_NOTES_FILE}" \
    "${TARBALL}#$(basename "${TARBALL}")" \
    "${SHA_FILE}#SHA-256 checksum" \
    "${TEST_RESULTS_FILE}#Full test suite results (${GPU_TUNED_VARIANT})" \
    "${SMOKE_FILE}#Package smoke test results (${GPU_TUNED_VARIANT})" \
    || exit 1

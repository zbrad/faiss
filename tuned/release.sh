#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/release.sh <variant> — publish the tarball tuned/package.sh made as a GitHub release, after the
# gates. Same stage order as raft, cuvs and llama.cpp:
#   tuned/build.sh -> tuned/wheel.sh -> tuned/full_test.sh -> tuned/package.sh -> tuned/smoke_test.sh
#   -> (review and commit tuned/releases/RELEASE_NOTES_<label>_<variant>_<cuda>.md) -> this.
# It never builds, tests or packages. docs/ARCHITECTURE.md (tuned-common) lists every gate below.
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
DIST_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/dist" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
OUTPUT_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
BUILD_DIR="$(gpu_tuned_cuda_subdir "${REPODIR}/_build" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
INFO="${DIST_DIR}/package-info.txt"
TEST_RESULTS_FILE="${OUTPUT_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"
SMOKE_FILE="${OUTPUT_DIR}/SMOKE_RESULTS_${GPU_TUNED_VARIANT}.log"
# The build-tree library is compared, not the staged one: package.sh rewrites the staged library (objcopy) on
# every run, so its mtime would move past the test results and the gate would pass only once per test run.
BUILT_LIB="${BUILD_DIR}/faiss/lib${FAISS_LIB_NAME}.so"

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { echo "  ok:   $*"; }

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

echo "Release ${RELEASE_TAG} (faiss ${SHORT_VER}, packaged at ${PACKAGED_COMMIT}):"

gpu_tuned_check_release_tag "${RELEASE_TAG}" && ok "tag carries a date label" || fail "tag ${RELEASE_TAG} carries no date label"

# Test gate: a passing full_test.sh log, newer than the build-tree library and the wheel.
if [[ ! -f "${BUILT_LIB}" ]]; then
    fail "${BUILT_LIB} not found -- cannot tell whether the test results are fresh; run tuned/build.sh ${GPU_TUNED_VARIANT}"
elif [[ ! -f "${TEST_RESULTS_FILE}" ]]; then
    fail "${TEST_RESULTS_FILE} not found -- run tuned/full_test.sh ${GPU_TUNED_VARIANT}"
elif [[ "${BUILT_LIB}" -nt "${TEST_RESULTS_FILE}" ]]; then
    fail "${BUILT_LIB} is newer than ${TEST_RESULTS_FILE}: the test results predate the build; re-run tuned/full_test.sh"
elif ! grep -q "Full test suite summary: pytest passed" "${TEST_RESULTS_FILE}"; then
    fail "${TEST_RESULTS_FILE} does not show a clean pass"
else
    ok "full test suite passed, log newer than the built library"
    mapfile -t WHEELS < <(find "${OUTPUT_DIR}" -maxdepth 1 -name 'faiss_*-py3-none-any.whl' -print)
    for w in "${WHEELS[@]}"; do
        [[ "${w}" -nt "${TEST_RESULTS_FILE}" ]] && fail "${w} is newer than the test log; re-run tuned/full_test.sh ${GPU_TUNED_VARIANT}"
    done
fi

# Package gate: the tarball matches package-info.txt, was made after the tests, and a passing smoke test of THIS
# tarball is newer than it.
if [[ ! -f "${TARBALL}" ]]; then
    fail "${TARBALL} not found"
else
    got="$(sha256sum "${TARBALL}" | awk '{print $1}')"
    [[ "${got}" == "$(info sha256)" ]] && ok "tarball sha256 matches package-info.txt" || fail "tarball sha256 does not match package-info.txt"
    if [[ -f "${TEST_RESULTS_FILE}" && "${TEST_RESULTS_FILE}" -nt "${TARBALL}" ]]; then
        fail "the test log is newer than the tarball; package again after testing"
    else
        ok "tarball was made after the tests"
    fi
    if [[ ! -f "${SMOKE_FILE}" ]]; then
        fail "${SMOKE_FILE} not found -- run tuned/smoke_test.sh ${GPU_TUNED_VARIANT}"
    elif [[ "${TARBALL}" -nt "${SMOKE_FILE}" ]]; then
        fail "${TARBALL} is newer than the smoke test log; re-run tuned/smoke_test.sh ${GPU_TUNED_VARIANT}"
    elif ! grep -q "Smoke test summary: passed" "${SMOKE_FILE}"; then
        fail "${SMOKE_FILE} does not show a pass"
    else
        ok "smoke test of this tarball passed"
    fi
fi
if ! { grep -qxF "cuda_tag=${FAISS_CUDA_TAG}" "${INFO}" && grep -qxF "variant=${GPU_TUNED_VARIANT}" "${INFO}"; }; then
    fail "package-info.txt is for another toolkit or variant"
fi

# Only the release notes may change between the packaged commit and HEAD.
changed="$(git diff --name-only "${PACKAGED_COMMIT}" HEAD -- . ':!tuned/releases' 2>/dev/null || echo '?')"
if [[ -z "${changed}" ]]; then
    ok "only release notes changed since the packaged commit ${PACKAGED_COMMIT}"
else
    fail "files other than tuned/releases/ changed since the packaged commit ${PACKAGED_COMMIT}: $(echo "${changed}" | head -3 | tr '\n' ' ')"
fi

# Release notes: a tracked, reviewed file, not a draft.
if [[ ! -f "${RELEASE_NOTES_FILE}" ]]; then
    fail "${RELEASE_NOTES_FILE} not found"
elif grep -q 'DRAFT — not yet published' "${RELEASE_NOTES_FILE}"; then
    fail "${RELEASE_NOTES_FILE} is still a draft (DRAFT banner present)"
elif ! git ls-files --error-unmatch "${RELEASE_NOTES_FILE}" >/dev/null 2>&1; then
    fail "${RELEASE_NOTES_FILE} is not committed"
else
    ok "release notes ${RELEASE_NOTES_FILE##*/} committed"
fi

if [[ ${FAILURES} -gt 0 ]]; then
    echo "" >&2
    echo "ERROR: ${FAILURES} gate(s) failed; nothing was published." >&2
    exit 1
fi

echo ""
echo "Publishing to GitHub release ${RELEASE_TAG}..."
gpu_tuned_publish_release "zbrad/faiss" "${RELEASE_TAG}" "${RELEASE_TITLE}" \
    "@${RELEASE_NOTES_FILE}" \
    "${TARBALL}#$(basename "${TARBALL}")" \
    "${TEST_RESULTS_FILE}#Full test suite results (${GPU_TUNED_VARIANT})" \
    "${SMOKE_FILE}#Package smoke test results (${GPU_TUNED_VARIANT})"

echo ""
echo "Release: https://github.com/zbrad/faiss/releases/tag/${RELEASE_TAG}"
echo "Done."

#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/smoke_test.sh <variant> — prove the PACKAGED tarball works, before it is released. Extracts the
# tarball tuned/package.sh made (named in package-info.txt) into a temporary directory and checks:
#   1. the tarball's sha256 matches package-info.txt;
#   2. the wheel's _swigfaiss.so resolves libfaiss-<variant>-<cuda>.so to a file inside the extracted tree
#      (not the build's stage directory), with the cuvs release's libraries on the path;
#   3. an import of faiss in a clean interpreter maps libfaiss from the extracted tree and the cuvs/rmm
#      libraries from the cuvs release directory, and nothing from the stage directory;
#   4. three real pytest files (tests/test_wheel_smoke_gpu.py, tests/test_index.py, tests/test_clustering.py)
#      pass in that environment.
# A smoke test, not the suite: tuned/full_test.sh already ran the whole suite against the build. What is new
# here is that the bits in the tarball are the ones running. Writes SMOKE_RESULTS_<variant>.log beside
# TEST_RESULTS; tuned/release.sh requires a passing log newer than the tarball.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -uo pipefail

GPU_TUNED_ARG_VARIANT="${1:?usage: tuned/smoke_test.sh <variant>}"
FAISS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${FAISS_ROOT}" || exit 1
# shellcheck source=env.sh
source "${FAISS_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

PYTHON="${PYTHON:-python3}"
PYTHON="$(command -v "${PYTHON}")" || { echo "ERROR: Python interpreter not found; set PYTHON." >&2; exit 1; }
TOOLKIT_LIB_DIR="${GPU_TUNED_TOOLKIT_LIB_DIR:-${CUDA_HOME}/lib64}"
[[ -d "${TOOLKIT_LIB_DIR}" ]] || { echo "ERROR: toolkit lib dir ${TOOLKIT_LIB_DIR} not found." >&2; exit 1; }
STAGE_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/_libfaiss_stage" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
OUTPUT_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
DIST_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/dist" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
CUVS_RELEASE_DIR="${FAISS_ROOT}/tuned/_cuvs_release/${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
TEST_ENV_DIR="${OUTPUT_DIR}/test_env"
INFO="${DIST_DIR}/package-info.txt"
LOG="${OUTPUT_DIR}/SMOKE_RESULTS_${GPU_TUNED_VARIANT}.log"
[[ -f "${INFO}" ]] || { echo "ERROR: ${INFO} not found. Run tuned/package.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }
[[ -d "${TEST_ENV_DIR}/faiss" && -d "${CUVS_RELEASE_DIR}/lib" ]] || { echo "ERROR: ${TEST_ENV_DIR}/faiss or ${CUVS_RELEASE_DIR}/lib missing; run tuned/full_test.sh ${GPU_TUNED_VARIANT} first." >&2; exit 1; }
info() { sed -n "s/^$1=//p" "${INFO}"; }
TARBALL="${DIST_DIR}/$(info tarball)"; WANT_SHA="$(info sha256)"; RELEASE_TAG="$(info release_tag)"
[[ -f "${TARBALL}" ]] || { echo "ERROR: ${TARBALL} not found." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
EXT="${WORK}/pkg"
mkdir -p "${EXT}"
fail() { echo "  FAIL: $*"; }
ok() { echo "  ok:   $*"; }

run() {
    echo "faiss package smoke test -- variant=${GPU_TUNED_VARIANT} cuda=${FAISS_CUDA_TAG}"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "release: ${RELEASE_TAG}"
    echo "tarball: $(basename "${TARBALL}")"
    echo ""

    local got lib maps foreign
    got="$(sha256sum "${TARBALL}" | awk '{print $1}')"
    [[ "${got}" == "${WANT_SHA}" ]] && ok "sha256 matches package-info.txt (${got:0:12}...)" || fail "sha256 ${got} != package-info.txt ${WANT_SHA}"

    tar -xzf "${TARBALL}" -C "${EXT}" || { fail "could not extract ${TARBALL}"; return; }
    lib="libfaiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"
    [[ -f "${EXT}/lib/${lib}" ]] && ok "extracts to a tree with lib/${lib} ($(find "${EXT}" -type f | wc -l) files)" || { fail "no lib/${lib} after extracting"; return; }

    export GPU_TUNED_SMOKE_LD_EXTRA="${CUVS_RELEASE_DIR}/lib:${TOOLKIT_LIB_DIR}"
    gpu_tuned_verify_resolves_in "${EXT}" "${TEST_ENV_DIR}/faiss/_swigfaiss.so" "^${lib//./\\.}" 2>&1 \
        && ok "_swigfaiss.so resolves ${lib} inside the package" || fail "_swigfaiss.so does not resolve ${lib} inside the package"

    export LD_LIBRARY_PATH="${EXT}/lib:${CUVS_RELEASE_DIR}/lib:${TOOLKIT_LIB_DIR}"
    export PYTHONPATH="${TEST_ENV_DIR}" PYTHONDONTWRITEBYTECODE=1
    maps="$("${PYTHON}" -c '
import faiss
print("gpus", faiss.get_num_gpus())
for line in open("/proc/self/maps"):
    p = line.split()[-1] if line.split() else ""
    if any(n in p for n in ("libfaiss", "libcuvs", "libraft", "librmm", "librapids_logger", "libkvikio")):
        print("map", p)
' 2>&1)" || { fail "import faiss failed: ${maps}"; return; }
    foreign="$(grep '^map ' <<< "${maps}" | grep -vE "^map (${EXT}|${CUVS_RELEASE_DIR})/" || true)"
    if [[ -n "${foreign}" ]]; then fail "libraries mapped from outside the package and the cuvs release: ${foreign}"
    elif grep -q "^map ${EXT}/lib/${lib}" <<< "${maps}" && ! grep -q "^map ${STAGE_DIR}/" <<< "${maps}"; then
        ok "an import maps ${lib} from the package ($(grep -c '^map ' <<< "${maps}") libraries, none from the build stage)"
    else fail "${lib} was not mapped from the package: ${maps}"; fi

    local out rc
    out="$("${PYTHON}" -m pytest tests/test_wheel_smoke_gpu.py tests/test_index.py tests/test_clustering.py -p no:cacheprovider -q --tb=short 2>&1)"; rc=$?
    if [[ ${rc} -eq 0 ]]; then
        ok "pytest (test_wheel_smoke_gpu, test_index, test_clustering): $(grep -E '[0-9]+ passed' <<< "${out}" | tail -1)"
    else
        fail "pytest exit ${rc}"; tail -20 <<< "${out}" | sed 's/^/        /'
    fi
    echo "  complete: every check ran"
}

run 2>&1 | tee "${LOG}"
echo "" >> "${LOG}"
# A pass needs the positive evidence: run() reached its end ("complete:") and nothing failed. An abort inside
# run() (an unset variable, a failed extract) leaves no FAIL line, and must not read as a pass.
if grep -q '^  FAIL:' "${LOG}" || ! grep -q '^  complete: every check ran' "${LOG}"; then
    echo "=== Smoke test summary: FAILED ===" | tee -a "${LOG}"
    echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LOG}"
    exit 1
fi
echo "=== Smoke test summary: passed ===" | tee -a "${LOG}"
echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LOG}"
echo "Results written to ${LOG}"

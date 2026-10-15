#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/full_test.sh <variant> — run faiss's pytest suite (tests/test_*.py)
# against the libraries and Python bindings built for ONE variant and ONE
# CUDA toolkit, and write a results log next to the wheel.
#
# Select the toolkit the way build.sh and wheel.sh do:
#   FAISS_CUDA_VER=13.3 bash tuned/full_test.sh gb10
#
# Requires tuned/build.sh <variant> (staged libfaiss) and tuned/wheel.sh
# <variant> (Python bindings) to have run for the same toolkit. The wheel is
# unpacked into build_output/<cuda_tag>/<variant>/test_env/ and used through
# PYTHONPATH, so nothing is pip-installed and a stock or other-toolkit faiss
# in site-packages cannot shadow the build under test. Before pytest starts,
# the script imports faiss and checks which libfaiss/libcuvs files the process
# actually mapped; it fails unless they are this toolkit's own.
#
# The results log is build_output/<cuda_tag>/<variant>/TEST_RESULTS_<variant>.log
# and ends with a "Full test suite summary" line.
export PATH="${CONDA_PREFIX:+$CONDA_PREFIX/bin:}$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

GPU_TUNED_ARG_VARIANT="$1"
FAISS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${FAISS_ROOT}" || exit 1

# shellcheck source=env.sh
source "${FAISS_ROOT}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1

PYTHON="${PYTHON:-python3}"
PYTHON="$(command -v "${PYTHON}")" || { echo "ERROR: Python interpreter '${PYTHON}' not found on PATH. Set PYTHON to an absolute path." >&2; exit 1; }

STAGE_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/_libfaiss_stage" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")" || exit 1
OUTPUT_DIR="$(gpu_tuned_cuda_subdir "${FAISS_ROOT}/build_output" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")" || exit 1
CUVS_RELEASE_DIR="${FAISS_ROOT}/tuned/_cuvs_release/${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}"
TEST_ENV_DIR="${OUTPUT_DIR}/test_env"
RESULTS_FILE="${OUTPUT_DIR}/TEST_RESULTS_${GPU_TUNED_VARIANT}.log"

[ -d "${STAGE_DIR}/lib" ] || { echo "ERROR: ${STAGE_DIR}/lib not found. Run tuned/build.sh ${GPU_TUNED_VARIANT} for ${FAISS_CUDA_TAG} first." >&2; exit 1; }
[ -d "${CUVS_RELEASE_DIR}/lib" ] || { echo "ERROR: ${CUVS_RELEASE_DIR}/lib not found. Run tuned/build.sh ${GPU_TUNED_VARIANT} for ${FAISS_CUDA_TAG} first." >&2; exit 1; }

# Exactly one wheel for this toolkit, newer than the staged library, so a
# stale wheel from an earlier build cannot be tested by mistake.
mapfile -t WHEELS < <(find "${OUTPUT_DIR}" -maxdepth 1 -name "faiss_*-py3-none-any.whl" -print)
[ "${#WHEELS[@]}" -eq 1 ] || { echo "ERROR: expected exactly one wheel in ${OUTPUT_DIR}, found ${#WHEELS[@]}. Run tuned/wheel.sh ${GPU_TUNED_VARIANT}." >&2; exit 1; }
WHEEL="${WHEELS[0]}"
STAGED_LIB="${STAGE_DIR}/lib/libfaiss-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"
[ -f "${STAGED_LIB}" ] || { echo "ERROR: ${STAGED_LIB} not found." >&2; exit 1; }
if [ "${STAGED_LIB}" -nt "${WHEEL}" ]; then
    echo "ERROR: ${STAGED_LIB} is newer than ${WHEEL}; rebuild the wheel with tuned/wheel.sh ${GPU_TUNED_VARIANT}." >&2
    exit 1
fi

mkdir -p "${TEST_ENV_DIR}"
"${PYTHON}" -I -m zipfile -e "${WHEEL}" "${TEST_ENV_DIR}" || { echo "ERROR: could not unpack ${WHEEL}." >&2; exit 1; }

export LD_LIBRARY_PATH="${STAGE_DIR}/lib:${CUVS_RELEASE_DIR}/lib:${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PYTHONPATH="${TEST_ENV_DIR}"
export PYTHONDONTWRITEBYTECODE=1

# Isolation check: list the shared objects the interpreter really mapped.
LOADED="$("${PYTHON}" -c '
import faiss
print("faiss", faiss.__version__, "gpus", faiss.get_num_gpus())
print("file", faiss.__file__)
for line in open("/proc/self/maps"):
    path = line.split()[-1] if line.split() else ""
    if any(n in path for n in ("libfaiss", "libcuvs", "libraft", "librmm", "librapids_logger", "libkvikio")):
        print("map", path)
' 2>&1)" || { echo "ERROR: import faiss failed:" >&2; echo "${LOADED}" >&2; exit 1; }
FOREIGN="$(echo "${LOADED}" | grep -E '^(file|map) ' | grep -vE "^(file|map) (${TEST_ENV_DIR}|${STAGE_DIR}|${CUVS_RELEASE_DIR})/" || true)"
if [ -n "${FOREIGN}" ]; then
    echo "ERROR: faiss loaded files from outside this toolkit's tree (${FAISS_CUDA_TAG}):" >&2
    echo "${FOREIGN}" >&2
    exit 1
fi

# Library-name gates, the same ones raft and cuvs apply when packaging: the rapids chain
# must be the unique "-tuned" names, and no stock RAPIDS name may be mapped or listed as
# NEEDED by our own libraries.
MAPPED_NAMES="$(echo "${LOADED}" | grep '^map ' | sed 's|^map .*/||' | sort -u)"
for need in librmm-tuned.so librapids_logger-tuned.so libkvikio-tuned.so; do
    echo "${MAPPED_NAMES}" | grep -qx "${need}" || { echo "ERROR: ${need} was not loaded; the -tuned rapids chain is not in use." >&2; echo "${MAPPED_NAMES}" >&2; exit 1; }
done
STOCK_RE='^(librmm|librapids_logger|libkvikio|libcuvs_c)\.so(\.[0-9.]+)?$'
STOCK_MAPPED="$(echo "${MAPPED_NAMES}" | grep -E "${STOCK_RE}" || true)"
[ -z "${STOCK_MAPPED}" ] || { echo "ERROR: stock RAPIDS libraries were loaded: ${STOCK_MAPPED}" >&2; exit 1; }
command -v readelf >/dev/null || { echo "ERROR: readelf not found; cannot check DT_NEEDED." >&2; exit 1; }
for so in "${TEST_ENV_DIR}/faiss/_swigfaiss.so" "${STAGED_LIB}" "${STAGE_DIR}/lib/libfaiss_c-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}.so"; do
    [ -f "${so}" ] || { echo "ERROR: ${so} not found for the DT_NEEDED check." >&2; exit 1; }
    STOCK_NEEDED="$(readelf -d "${so}" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -E "${STOCK_RE}" || true)"
    [ -z "${STOCK_NEEDED}" ] || { echo "ERROR: ${so} lists stock RAPIDS libraries as NEEDED: ${STOCK_NEEDED}" >&2; exit 1; }
done
# nvtx3 must ship in the cuvs release this build linked against (the packaging fix).
[ -f "${CUVS_RELEASE_DIR}/lib/cmake/nvtx3/nvtx3-config.cmake" ] && [ -f "${CUVS_RELEASE_DIR}/include/nvtx3/nvtx3.hpp" ] \
    || { echo "ERROR: nvtx3 is missing from ${CUVS_RELEASE_DIR}; that cuvs release predates the nvtx3 fix." >&2; exit 1; }

{
    echo "faiss full test suite -- variant=${GPU_TUNED_VARIANT} cuda=${FAISS_CUDA_VER} (${FAISS_CUDA_TAG})"
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit:  $(git -C "${FAISS_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "wheel:   $(basename "${WHEEL}")"
    echo "${LOADED}"
    echo "gates: -tuned rapids chain mapped, no stock RAPIDS names mapped or NEEDED, nvtx3 in cuvs release"
    echo "excluded: tests/external_module_test.py (needs the separately built faiss_example_external_module)"
    echo ""
} > "${RESULTS_FILE}"

# pipefail: the exit status below must be pytest's, not tee's.
set -o pipefail
# tests/external_module_test.py needs faiss.faiss_example_external_module, a separate
# example extension that neither build.sh nor wheel.sh builds; collecting it aborts the
# whole run, so it is excluded (and the exclusion is recorded in the log header).
"${PYTHON}" -m pytest tests --ignore=tests/external_module_test.py -p no:cacheprovider -q -rfEs --tb=short 2>&1 | tee -a "${RESULTS_FILE}"
STATUS=$?

echo "" >> "${RESULTS_FILE}"
if [ "${STATUS}" -eq 0 ]; then
    echo "=== Full test suite summary: pytest passed ===" | tee -a "${RESULTS_FILE}"
else
    echo "=== Full test suite summary: pytest FAILED (exit ${STATUS}) ===" | tee -a "${RESULTS_FILE}"
fi
echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${RESULTS_FILE}"
echo "Results written to ${RESULTS_FILE}"
exit "${STATUS}"

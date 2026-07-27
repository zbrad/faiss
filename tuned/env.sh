#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/env.sh <variant> — single source of truth for a tuned build's CUDA
# toolkit selection AND its device metadata (gb10/rtx40/rtx50). Source this
# file with the variant as $1; do not execute it directly.
#
# Consolidates what used to be gpu-cu/scripts/cuda_env.sh (FAISS_CUDA_VER/
# FAISS_CUDA_TAG/CUDA_HOME detection, identical logic, just relocated) plus
# the device-specific values that used to be hardcoded separately across
# build_lib_*.sh/build_pkg_*.sh/package_wheel_*.sh/wsl/env_rtx*.sh -- now in
# tuned/devices/<variant>.conf, one file per variant.
#
# Specify the CUDA version at build time with EITHER variable (unchanged):
#   FAISS_CUDA_VER=13.3  bash tuned/build.sh gb10
#   FAISS_CUDA_TAG=cu133 bash tuned/build.sh gb10
#
# Exported: FAISS_CUDA_VER/FAISS_CUDA_TAG/CUDA_HOME (this repo's own
# naming, unchanged), GPU_TUNED_VARIANT/CUDA_ARCH/HW_LABEL/BLAS/
# OPENBLAS_LIB/MKL_ROOT/OPT_LEVEL/SWIG_TARGETS/MAKE_TARGETS/
# USES_LOCAL_CUVS (from tuned/devices/<variant>.conf).
#
# Also defines gpu_tuned_verify_arch() -- NEW, this repo previously had no
# empirical "did the build actually target the requested arch" check at
# all (confirmed via this session's gap analysis), unlike zbrad/cuvs and
# zbrad/raft, which both already had (or were given) one. Same
# cuobjdump-based approach, same function name, for consistency.

GPU_TUNED_ARG_VARIANT="$1"
if [[ -z "${GPU_TUNED_ARG_VARIANT}" ]]; then
    echo "ERROR: env.sh requires a variant argument (gb10/rtx40/rtx50)" >&2
    return 1 2>/dev/null || exit 1
fi

GPU_TUNED_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=devices/rtx50.conf
source "${GPU_TUNED_SELF_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL GPU_TUNED_BLAS \
    GPU_TUNED_OPENBLAS_LIB GPU_TUNED_MKL_ROOT GPU_TUNED_OPT_LEVEL \
    GPU_TUNED_SWIG_TARGETS GPU_TUNED_MAKE_TARGETS GPU_TUNED_USES_LOCAL_CUVS

# --- Resolve FAISS_CUDA_VER / FAISS_CUDA_TAG (specify either, derive the other) ---
if [ -n "${FAISS_CUDA_VER:-}" ]; then
    : "${FAISS_CUDA_TAG:=cu${FAISS_CUDA_VER//./}}"
elif [ -n "${FAISS_CUDA_TAG:-}" ]; then
    _faiss_cuda_digits="${FAISS_CUDA_TAG#cu}"
    : "${FAISS_CUDA_VER:=${_faiss_cuda_digits%?}.${_faiss_cuda_digits: -1}}"
    unset _faiss_cuda_digits
fi
export FAISS_CUDA_VER="${FAISS_CUDA_VER:-13.2}"
export FAISS_CUDA_TAG="${FAISS_CUDA_TAG:-cu${FAISS_CUDA_VER//./}}"

faiss_installed_cuda_toolkits() {
    local d
    for d in /usr/local/cuda-[0-9]*; do
        [ -d "$d" ] && basename "$d" | sed 's/^cuda-//'
    done | sort -V
}

# --- Resolve CUDA_HOME to the matching toolkit when not explicitly set ---
if [ -z "${CUDA_HOME:-}" ]; then
    if [ -d "/usr/local/cuda-${FAISS_CUDA_VER}" ]; then
        export CUDA_HOME="/usr/local/cuda-${FAISS_CUDA_VER}"
    else
        echo "[tuned/env] WARNING: /usr/local/cuda-${FAISS_CUDA_VER} not found; falling back to /usr/local/cuda (whatever version that symlinks to)." >&2
        _faiss_installed="$(faiss_installed_cuda_toolkits | tr '\n' ' ')"
        if [ -n "$_faiss_installed" ]; then
            echo "[tuned/env]          Installed toolkits: ${_faiss_installed}. Set FAISS_CUDA_VER to one of these, or CUDA_HOME to an explicit path." >&2
        else
            echo "[tuned/env]          No /usr/local/cuda-<ver> toolkits found at all." >&2
        fi
        unset _faiss_installed
        export CUDA_HOME="/usr/local/cuda"
    fi
fi
export PATH="$CUDA_HOME/bin:$PATH"

# --- Sanity: warn if the resolved nvcc does not match the requested version ---
if command -v nvcc >/dev/null 2>&1; then
    _faiss_nvcc_ver="$(nvcc --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | awk '{print $2}')"
    if [ -n "$_faiss_nvcc_ver" ] && [ "$_faiss_nvcc_ver" != "$FAISS_CUDA_VER" ]; then
        echo "[tuned/env] WARNING: nvcc reports CUDA $_faiss_nvcc_ver but FAISS_CUDA_VER=$FAISS_CUDA_VER" >&2
        echo "[tuned/env]          (CUDA_HOME=$CUDA_HOME). Set CUDA_HOME or FAISS_CUDA_VER to match." >&2
        _faiss_installed="$(faiss_installed_cuda_toolkits | tr '\n' ' ')"
        [ -n "$_faiss_installed" ] && echo "[tuned/env]          Installed toolkits: ${_faiss_installed}" >&2
        unset _faiss_installed
    fi
    unset _faiss_nvcc_ver
fi

# gpu_tuned_verify_arch <path-to-.so> — confirms a compiled library's
# embedded cubin(s) are EXACTLY sm_${GPU_TUNED_CUDA_ARCH}, via cuobjdump.
# Same name/signature as zbrad/cuvs's and zbrad/raft's tuned/env.sh
# equivalents.
gpu_tuned_verify_arch() {
    local so_file="$1"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: gpu_tuned_verify_arch: no such file: ${so_file}" >&2
        return 1
    fi
    command -v cuobjdump >/dev/null 2>&1 || {
        echo "ERROR: gpu_tuned_verify_arch: cuobjdump not found on PATH (expected under \$CUDA_HOME/bin)." >&2
        return 1
    }
    local found found_count
    found="$(cuobjdump --list-elf "${so_file}" 2>/dev/null | grep -oE 'sm_[0-9]+[a-z]?' | sort -u)"
    if [[ -z "${found}" ]]; then
        echo "ERROR: gpu_tuned_verify_arch: cuobjdump found no embedded cubins in ${so_file} at all." >&2
        return 1
    fi
    found_count="$(echo "${found}" | wc -l)"
    if [[ "${found_count}" -ne 1 ]]; then
        echo "ERROR: ${so_file} embeds MULTIPLE arch targets ($(echo "${found}" | tr '\n' ' ')) -- this is supposed to be a single-arch tuned build, not a fat multi-arch one." >&2
        return 1
    fi
    if [[ "${found}" != "sm_${GPU_TUNED_CUDA_ARCH}" ]]; then
        echo "ERROR: ${so_file} is not built for sm_${GPU_TUNED_CUDA_ARCH} (found: ${found})." >&2
        return 1
    fi
    echo "OK: ${so_file} confirmed single-arch ${found} (matches requested sm_${GPU_TUNED_CUDA_ARCH})"
}

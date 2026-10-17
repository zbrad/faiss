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
# build_lib_*.sh/build_pkg_*.sh/package_wheel_*.sh/wsl/env_rtx*.sh -- now the
# shared device files in tuned/common-data/devices/<variant>.conf
# (zbrad/tuned-common) plus faiss's own per-variant build settings in
# tuned/repo.env.
#
# The toolkit comes from the vendored definitions in tuned/common-data/toolkits/<id>.env,
# never from /usr/local/cuda or from what is installed. There is no default: name it with
# EITHER variable (the other is derived; CUDA_VER / CUDA_TAG are accepted too):
#   FAISS_CUDA_VER=13.3  bash tuned/build.sh gb10
#   FAISS_CUDA_TAG=cu133 bash tuned/build.sh gb10
# With neither set the loader fails and lists the defined toolkits (at a terminal it asks
# which to use, for that run only).
#
# Exported: FAISS_CUDA_VER/FAISS_CUDA_TAG/CUDA_HOME (this repo's own
# naming, unchanged; CUDA_VER/CUDA_TAG too), GPU_TUNED_VARIANT/PLATFORM/CUDA_ARCH/HW_LABEL
# (shared device file), GPU_TUNED_BLAS/OPENBLAS_LIB/MKL_ROOT/OPT_LEVEL/SWIG_TARGETS/
# MAKE_TARGETS (from tuned/repo.env).
#
# Also defines gpu_tuned_verify_arch(), gpu_tuned_verify_cuda_compat(), and
# embed_build_info() -- NEW, this repo previously had none of these
# empirical checks at all (confirmed via this session's gap analysis),
# unlike zbrad/cuvs and zbrad/raft, which both already had (or were given)
# equivalents. Same names/signatures, for consistency.

GPU_TUNED_ARG_VARIANT="$1"
if [[ -z "${GPU_TUNED_ARG_VARIANT}" ]]; then
    echo "ERROR: env.sh requires a variant argument (gb10/rtx40/rtx50)" >&2
    return 1 2>/dev/null || exit 1
fi

GPU_TUNED_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_TUNED_DATA_DIR="${GPU_TUNED_SELF_DIR}/common-data"
# shellcheck source=common-data/devices/gb10.conf
source "${GPU_TUNED_DATA_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL

# shellcheck source=common.sh
# Vendored from https://github.com/zbrad/tuned-common (pinned commit --
# see common.sh's own header/sync instructions to update). Provides
# gpu_tuned_verify_arch/verify_cuda_compat/assert_platform/
# installed_cuda_toolkits, shared verbatim across the fleet instead of
# hand-copied-and-edited per repo. NOT used for embed_build_info here:
# this repo stamps every package into the SAME .faiss_build_info section
# rather than one section per package -- kept local on purpose (same
# reasoning as zbrad/raft's/zbrad/cuvs's tuned/env.sh).
source "${GPU_TUNED_SELF_DIR}/common.sh" || return 1 2>/dev/null || exit 1

# Fail loudly if this script runs on the wrong host, rather than letting a
# mismatched build silently produce wrong-architecture binaries that only
# surface as a confusing failure several steps later. Same check as
# zbrad/cuvs's, zbrad/raft's, and zbrad/flash-attention's tuned/env.sh --
# this repo previously had no equivalent at all.
gpu_tuned_assert_platform "${GPU_TUNED_PLATFORM}" "${GPU_TUNED_VARIANT}" || return 1 2>/dev/null || exit 1

# --- CUDA toolkit: chosen from tuned/common-data/toolkits, never inferred. FAISS_CUDA_TAG (cu133) or
#     FAISS_CUDA_VER (13.3) select one (CUDA_TAG / CUDA_VER likewise); neither set is an error listing
#     the defined ones (no default). Exports CUDA_VER, CUDA_TAG, CUDA_HOME and puts $CUDA_HOME/bin on PATH. ---
_faiss_tk="${FAISS_CUDA_TAG:-${CUDA_TAG:-}}"
_faiss_req_ver="${FAISS_CUDA_VER:-${CUDA_VER:-}}"
if [ -z "${_faiss_tk}" ] && [ -n "${_faiss_req_ver}" ]; then
    _faiss_tk="cu${_faiss_req_ver//./}"                         # 13.3 -> cu133
fi
gpu_tuned_load_toolkit "${GPU_TUNED_DATA_DIR}" "${GPU_TUNED_VARIANT}" "${_faiss_tk}" || return 1 2>/dev/null || exit 1
if [ -n "${_faiss_req_ver}" ] && [ "${_faiss_req_ver}" != "${TOOLKIT_CUDA_VER}" ]; then
    echo "[tuned/env] ERROR: CUDA version ${_faiss_req_ver} conflicts with toolkit ${CUDA_TAG} (CUDA ${TOOLKIT_CUDA_VER})." >&2
    return 1 2>/dev/null || exit 1
fi
unset _faiss_tk _faiss_req_ver
gpu_tuned_verify_toolkit || return 1 2>/dev/null || exit 1
# faiss's own names for the toolkit, used throughout tuned/.
export FAISS_CUDA_VER="${CUDA_VER}" FAISS_CUDA_TAG="${CUDA_TAG}"

# --- Repo-specific settings (BLAS, SIMD level, SWIG and make targets), loaded last; may not change
#     any shared device/toolkit key. ---
gpu_tuned_load_repo_env "${GPU_TUNED_SELF_DIR}/repo.env" || return 1 2>/dev/null || exit 1
export GPU_TUNED_BLAS GPU_TUNED_OPENBLAS_LIB GPU_TUNED_MKL_ROOT GPU_TUNED_OPT_LEVEL \
    GPU_TUNED_SWIG_TARGETS GPU_TUNED_MAKE_TARGETS

# embed_build_info now comes from common.sh (gpu_tuned_embed_build_info) --
# every call site in this repo already passes package="faiss", so the
# shared function's package-derived section name naturally lands on the
# same .faiss_build_info this repo always used, and its message format is
# byte-identical to what the old local version produced. Wrap it just to
# keep call sites unchanged (repo_url baked in here).
embed_build_info() {
    gpu_tuned_embed_build_info "$1" "$2" "$3" "$4" "$5" "https://github.com/zbrad/faiss"
}

# gpu_tuned_verify_pin_honored <package-name> <pinned-dir> <actual-dir>
# Confirms CMake actually used the exact directory we explicitly pinned
# via -D<Package>_DIR=..., rather than silently overriding it and falling
# back to its own broader search. This is a STRONGER, more direct check
# than gpu_tuned_verify_cccl_toolkit_match below: CMake's find_package
# silently discards an explicit _DIR hint that fails a version constraint
# (e.g. PACKAGE_FIND_VERSION) and searches elsewhere instead, with no
# error of its own -- confirmed empirically: an explicit CUB_DIR pin at
# CUDA_HOME=13.2 (bundled CCCL 3.2.0, below the 3.3.3 minimum this build
# needed) was silently ignored, and the ONLY visible symptom was the
# final resolved path being different -- no CMake warning or error
# flagged the override itself. Waiting to see whether the resulting
# version happens to still satisfy a loose min-major/warn-on-minor check
# (gpu_tuned_verify_cccl_toolkit_match) is not good enough: a rejected
# pin means our intent was silently discarded, which is exactly the class
# of surprising, silent drift this whole tuned-builds convention exists
# to eliminate -- so this is unconditionally fatal, not a warning,
# regardless of what the fallback happened to land on.
gpu_tuned_verify_pin_honored() {
    local pkg_name="$1" pinned_dir="$2" actual_dir="$3"
    if [[ -z "${pinned_dir}" ]]; then
        return 0  # we never pinned this package -- nothing to verify
    fi
    if [[ "$(readlink -f "${pinned_dir}" 2>/dev/null)" != "$(readlink -f "${actual_dir}" 2>/dev/null)" ]]; then
        echo "ERROR: explicit -D${pkg_name}_DIR=\"${pinned_dir}\" was silently overridden by CMake" >&2
        echo "  (actually resolved to \"${actual_dir}\"). This means CUDA_HOME's own bundled" >&2
        echo "  ${pkg_name} failed CMake's version check (PACKAGE_FIND_VERSION) and was rejected --" >&2
        echo "  CMake does not surface this as its own warning or error, it just searches" >&2
        echo "  elsewhere. Upgrade to a newer CUDA_HOME toolkit, or investigate why the pin" >&2
        echo "  failed, rather than trusting whatever CMake's fallback search happened to find." >&2
        return 1
    fi
    echo "OK: ${pkg_name} used the explicitly pinned directory (${actual_dir})"
}

# gpu_tuned_verify_cccl_toolkit_match <resolved-dir> <package-name>
#                                     <expected-cuda-ver>
# Extracts a CUDA major.minor embedded in a resolved CMake package
# directory's path (e.g. .../cuda-13.2/... or .../CUDA/v13.3/...) and
# compares it against the toolkit this build is actually using
# (CUDA_HOME's own version). Real gap this closes: CMake's
# find_package(CUB/Thrust/libcudacxx/CCCL CONFIG) -- triggered by
# cuvs-dependencies.cmake's find_dependency(CCCL) chain -- searches
# broadly and can resolve to a DIFFERENT installed CUDA toolkit than the
# one nvcc itself is using. Confirmed empirically: WSL's default
# Windows-PATH interop exposes side-by-side Windows CUDA installs
# (multiple versions), and one of them won this search ahead of the
# Linux toolkit's own bundled copy, even though CUDA_HOME/PATH correctly
# steered nvcc itself to the intended toolkit.
#
# MAJOR mismatch is always fatal (real ABI break risk, same philosophy
# as gpu_tuned_verify_cuda_compat). MINOR mismatch warns by default
# (CCCL is largely header-only and version-tolerant within a major
# series) -- set GPU_TUNED_STRICT_TOOLKIT_MATCH=1 to make ANY
# difference (including minor) fatal.
gpu_tuned_verify_cccl_toolkit_match() {
    local dep_dir="$1" pkg_name="$2" expected_cuda_ver="$3"
    if [[ -z "${dep_dir}" || ! -d "${dep_dir}" ]]; then
        echo "NOTE: gpu_tuned_verify_cccl_toolkit_match: no resolved directory for ${pkg_name} -- skipping." >&2
        return 0
    fi
    local found_ver
    found_ver="$(echo "${dep_dir}" | grep -oE '(cuda-|CUDA/v)[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    if [[ -z "${found_ver}" ]]; then
        echo "NOTE: gpu_tuned_verify_cccl_toolkit_match: could not extract a CUDA version from" \
             "${pkg_name}'s resolved path (${dep_dir}) -- skipping version comparison." >&2
        return 0
    fi
    local found_major="${found_ver%%.*}" found_minor="${found_ver#*.}"
    local expected_major="${expected_cuda_ver%%.*}" expected_minor="${expected_cuda_ver#*.}"
    if [[ "${found_major}" != "${expected_major}" ]]; then
        echo "ERROR: ${pkg_name} resolved to CUDA ${found_ver} (${dep_dir}), but this build is" \
             "using CUDA ${expected_cuda_ver} (CUDA_HOME=${CUDA_HOME:-<unset>}) -- MAJOR version" \
             "mismatch, real ABI break risk." >&2
        return 1
    fi
    if [[ "${found_minor}" != "${expected_minor}" ]]; then
        if [[ "${GPU_TUNED_STRICT_TOOLKIT_MATCH:-0}" == "1" ]]; then
            echo "ERROR: ${pkg_name} resolved to CUDA ${found_ver} (${dep_dir}), but this build is" \
                 "using CUDA ${expected_cuda_ver} -- minor version mismatch, and" \
                 "GPU_TUNED_STRICT_TOOLKIT_MATCH=1 requires an exact major.minor match." >&2
            return 1
        fi
        echo "WARNING: ${pkg_name} resolved to CUDA ${found_ver} (${dep_dir}), but this build is" \
             "using CUDA ${expected_cuda_ver} -- minor version differs. Usually fine (CCCL is" \
             "largely header-only and version-tolerant within a major series), but set" \
             "GPU_TUNED_STRICT_TOOLKIT_MATCH=1 to make this fatal." >&2
        return 0
    fi
    echo "OK: ${pkg_name} resolved to CUDA ${found_ver}, matches this build's CUDA ${expected_cuda_ver}"
}

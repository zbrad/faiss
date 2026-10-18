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

# --- CUDA toolkit: named by FAISS_CUDA_TAG (cu133) or FAISS_CUDA_VER (13.3), CUDA_TAG / CUDA_VER likewise, never
#     defaulted or guessed; loaded from tuned/common-data/toolkits and verified (docs/ARCHITECTURE.md B4). Exports
#     CUDA_VER, CUDA_TAG, CUDA_HOME and puts $CUDA_HOME/bin on PATH. ---
GPU_TUNED_TOOLKIT_ENV_PREFIX=FAISS_ gpu_tuned_select_toolkit "${GPU_TUNED_DATA_DIR}" "${GPU_TUNED_VARIANT}" || return 1 2>/dev/null || exit 1
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

# --- Output layout: one tree per toolkit, tuned/build/<cuda-tag>/ (gitignored), with no variant level
#     (docs/ARCHITECTURE.md C2). cmake/ is the one fixed compile path; stage/ the staged libfaiss;
#     cuvs/ the extracted cuvs release it links; python/<ver>/ the wheel's build tree; wheel/ the wheel;
#     test_env/ the unpacked wheel under test; dist/ the tarball + sidecar + package-info.txt;
#     releases/ the generated test and smoke logs (tracked RELEASE_NOTES_*.md stay in tuned/releases/).
#     The claim refuses a tree last used by another variant. ---
GPU_TUNED_REPO_ROOT="$(cd "${GPU_TUNED_SELF_DIR}/.." && pwd)"
gpu_tuned_claim_toolkit_tree "${GPU_TUNED_REPO_ROOT}" "${CUDA_TAG}" "${GPU_TUNED_VARIANT}" || return 1 2>/dev/null || exit 1
GPU_TUNED_BUILD_ROOT="${GPU_TUNED_REPO_ROOT}/tuned/build/${CUDA_TAG}"
export CCACHE_DIR="${GPU_TUNED_BUILD_ROOT}/ccache"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-40G}"
export GPU_TUNED_BUILD_ROOT

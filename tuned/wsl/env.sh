#!/bin/bash
# tuned/wsl/env.sh <variant> — WSL/PowerShell entry point for sourcing the
# tuned build environment (rtx40/rtx50 only -- gb10/DGX Spark is a native
# Linux aarch64 target, not a Windows/WSL one).
#   source tuned/wsl/env.sh rtx50
#
# Consolidates what used to be two separate files (env_rtx40.sh,
# env_rtx50.sh) -- both were otherwise-identical sourcing wrappers around
# gpu-cu/scripts/cuda_env.sh with the variant's values hardcoded. Now just
# sources tuned/env.sh (the real single source of truth) and re-exports the
# same WSL-friendly variable names for any external automation that already
# expects them.

_wsl_variant="$1"
_wsl_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAISS_ROOT="$(cd "$_wsl_script_dir/../.." && pwd)"
export FAISS_ROOT
unset _wsl_script_dir

# shellcheck source=../env.sh
source "${FAISS_ROOT}/tuned/env.sh" "${_wsl_variant}"
unset _wsl_variant

export MKL_ROOT="${GPU_TUNED_MKL_ROOT:-}"
[ -n "$MKL_ROOT" ] && export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$MKL_ROOT/lib:${LD_LIBRARY_PATH:-}"
[ -n "$MKL_ROOT" ] && export MKL_INCLUDE_DIR="$MKL_ROOT/include"
[ -n "$MKL_ROOT" ] && export MKL_LIB="$MKL_ROOT/lib/libmkl_rt.so"

export CUDA_ARCHS="${GPU_TUNED_CUDA_ARCH}"
export FAISS_VARIANT="${FAISS_VARIANT:-${GPU_TUNED_VARIANT}-${FAISS_CUDA_TAG}}"

echo "[env] CUDA_VER     = $FAISS_CUDA_VER (tag $FAISS_CUDA_TAG)"
echo "[env] CUDA_HOME    = $CUDA_HOME"
[ -n "$MKL_ROOT" ] && echo "[env] MKL_ROOT     = $MKL_ROOT"
echo "[env] CUDA_ARCHS   = $CUDA_ARCHS ($GPU_TUNED_HW_LABEL)"
echo "[env] FAISS_VARIANT= $FAISS_VARIANT"
echo "[env] FAISS_ROOT   = $FAISS_ROOT"

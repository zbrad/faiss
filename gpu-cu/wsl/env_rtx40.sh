#!/bin/bash
# WSL build environment for FAISS GPU — RTX 40 / Ada Lovelace (x86_64, Intel MKL).
# Source this file before running any build step:
#   source gpu-cu/wsl/env_rtx40.sh

# Repo root: inferred from this script's own location (wsl/ -> gpu-cu/ ->
# repo root), not a hardcoded drive-letter guess. Override FAISS_ROOT
# explicitly if you're sourcing a copy of this file from elsewhere.
_wsl_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FAISS_ROOT="${FAISS_ROOT:-$(cd "$_wsl_script_dir/../.." && pwd)}"
unset _wsl_script_dir

# CUDA version + CUDA_HOME resolution (single source of truth).
# Override the version per-invocation, e.g.:  FAISS_CUDA_VER=13.3 source gpu-cu/wsl/env_rtx40.sh
source "$FAISS_ROOT/gpu-cu/scripts/cuda_env.sh"

# CUDA_HOME is resolved by cuda_env.sh (versioned toolkit if present); keep it.
export MKL_ROOT=/opt/intel/oneapi/mkl/latest

export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$MKL_ROOT/lib:${LD_LIBRARY_PATH:-}"

export MKL_INCLUDE_DIR="$MKL_ROOT/include"
export MKL_LIB="$MKL_ROOT/lib/libmkl_rt.so"

# Single-arch: RTX 40 / Ada Lovelace (SM 89) only -- matches gpu-cu/scripts/
# build_lib_rtx40.sh and zbrad/cuvs's own tuned/build.sh rtx40. Not
# overridable via CUDA_ARCHS anymore; use env_rtx50.sh for Blackwell.
export CUDA_ARCHS="89"

# Wheel package name: faiss-{FAISS_VARIANT}, e.g. faiss-rtx40-cu132. CPU arch
# is carried by the wheel's manylinux platform tag (x86_64 here), not the
# name; the codename alone already implies exactly one GPU arch, so there's
# no separate -sm<arch> suffix (matches gpu-cu/scripts/package_wheel_rtx40.sh).
export FAISS_VARIANT="${FAISS_VARIANT:-rtx40-${FAISS_CUDA_TAG}}"

echo "[env] CUDA_VER     = $FAISS_CUDA_VER (tag $FAISS_CUDA_TAG)"
echo "[env] CUDA_HOME    = $CUDA_HOME"
echo "[env] MKL_ROOT     = $MKL_ROOT"
echo "[env] CUDA_ARCHS   = $CUDA_ARCHS (Ada Lovelace, RTX 4080/4090)"
echo "[env] FAISS_VARIANT= $FAISS_VARIANT"
echo "[env] FAISS_ROOT   = $FAISS_ROOT"

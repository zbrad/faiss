#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Single source of truth for the CUDA version targeted by this toolkit.
# All build scripts source this file.
#
# Specify the version at build time with EITHER variable (the other is derived):
#
#   FAISS_CUDA_VER=13.3  make build            # human-readable version
#   FAISS_CUDA_TAG=cu133 make build            # short wheel/library tag
#
# Defaults to CUDA 13.2 (cu132) when neither is set.
#
# Derived everywhere as:
#   wheel/package name : faiss-{codename}-${FAISS_CUDA_TAG}  (codename: gb10/rtx40/rtx50)
#   C++ library names  : libfaiss-{codename}-${FAISS_CUDA_TAG}.so
#
# On a host with multiple toolkits installed (e.g. /usr/local/cuda-13.2 and
# /usr/local/cuda-13.3), CUDA_HOME is auto-resolved to the directory matching
# the requested version, so the correct nvcc is used. An explicit CUDA_HOME
# always wins.

# --- Resolve FAISS_CUDA_VER / FAISS_CUDA_TAG (specify either, derive the other) ---
if [ -n "${FAISS_CUDA_VER:-}" ]; then
    : "${FAISS_CUDA_TAG:=cu${FAISS_CUDA_VER//./}}"          # 13.3 -> cu133
elif [ -n "${FAISS_CUDA_TAG:-}" ]; then
    _faiss_cuda_digits="${FAISS_CUDA_TAG#cu}"               # cu133 -> 133
    : "${FAISS_CUDA_VER:=${_faiss_cuda_digits%?}.${_faiss_cuda_digits: -1}}"  # 133 -> 13.3
    unset _faiss_cuda_digits
fi
export FAISS_CUDA_VER="${FAISS_CUDA_VER:-13.2}"
export FAISS_CUDA_TAG="${FAISS_CUDA_TAG:-cu${FAISS_CUDA_VER//./}}"

# List installed toolkits under /usr/local/cuda-<ver> (glob, sorted). Used to
# give actionable guidance instead of a bare "wrong version" warning.
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
        echo "[cuda_env] WARNING: /usr/local/cuda-${FAISS_CUDA_VER} not found; falling back to /usr/local/cuda (whatever version that symlinks to)." >&2
        _faiss_installed="$(faiss_installed_cuda_toolkits | tr '\n' ' ')"
        if [ -n "$_faiss_installed" ]; then
            echo "[cuda_env]          Installed toolkits: ${_faiss_installed}. Set FAISS_CUDA_VER to one of these, or CUDA_HOME to an explicit path." >&2
        else
            echo "[cuda_env]          No /usr/local/cuda-<ver> toolkits found at all." >&2
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
        echo "[cuda_env] WARNING: nvcc reports CUDA $_faiss_nvcc_ver but FAISS_CUDA_VER=$FAISS_CUDA_VER" >&2
        echo "[cuda_env]          (CUDA_HOME=$CUDA_HOME). Set CUDA_HOME or FAISS_CUDA_VER to match." >&2
        _faiss_installed="$(faiss_installed_cuda_toolkits | tr '\n' ' ')"
        [ -n "$_faiss_installed" ] && echo "[cuda_env]          Installed toolkits: ${_faiss_installed}" >&2
        unset _faiss_installed
    fi
    unset _faiss_nvcc_ver
fi

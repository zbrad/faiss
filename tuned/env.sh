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
# naming, unchanged), GPU_TUNED_VARIANT/PLATFORM/CUDA_ARCH/HW_LABEL/BLAS/
# OPENBLAS_LIB/MKL_ROOT/OPT_LEVEL/SWIG_TARGETS/MAKE_TARGETS (from
# tuned/devices/<variant>.conf).
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
# shellcheck source=devices/rtx50.conf
source "${GPU_TUNED_SELF_DIR}/devices/${GPU_TUNED_ARG_VARIANT}.conf" || return 1 2>/dev/null || exit 1
export GPU_TUNED_VARIANT GPU_TUNED_PLATFORM GPU_TUNED_CUDA_ARCH GPU_TUNED_HW_LABEL GPU_TUNED_BLAS \
    GPU_TUNED_OPENBLAS_LIB GPU_TUNED_MKL_ROOT GPU_TUNED_OPT_LEVEL \
    GPU_TUNED_SWIG_TARGETS GPU_TUNED_MAKE_TARGETS

# Fail loudly if this script runs on the wrong host, rather than letting a
# mismatched build silently produce wrong-architecture binaries that only
# surface as a confusing failure several steps later. Same check as
# zbrad/cuvs's, zbrad/raft's, and zbrad/flash-attention's tuned/env.sh --
# this repo previously had no equivalent at all.
if [[ "$(uname -m)" != "${GPU_TUNED_PLATFORM}" ]]; then
    echo "ERROR: tuned/env.sh: expected platform '${GPU_TUNED_PLATFORM}' for" \
         "variant '${GPU_TUNED_VARIANT}', but uname -m reports '$(uname -m)'." >&2
    return 1 2>/dev/null || exit 1
fi

# List installed toolkits under /usr/local/cuda-<ver> (glob, sorted). Used
# both to derive the default FAISS_CUDA_VER below (highest installed, not
# a hardcoded version that inevitably goes stale -- e.g. this default was
# "13.2" even after 13.3 was installed here) and to give actionable
# guidance instead of a bare "wrong version" warning.
faiss_installed_cuda_toolkits() {
    local d
    for d in /usr/local/cuda-[0-9]*; do
        [ -d "$d" ] && basename "$d" | sed 's/^cuda-//'
    done | sort -V
}

# --- Resolve FAISS_CUDA_VER / FAISS_CUDA_TAG (specify either, derive the other) ---
if [ -n "${FAISS_CUDA_VER:-}" ]; then
    : "${FAISS_CUDA_TAG:=cu${FAISS_CUDA_VER//./}}"
elif [ -n "${FAISS_CUDA_TAG:-}" ]; then
    _faiss_cuda_digits="${FAISS_CUDA_TAG#cu}"
    : "${FAISS_CUDA_VER:=${_faiss_cuda_digits%?}.${_faiss_cuda_digits: -1}}"
    unset _faiss_cuda_digits
fi
if [ -z "${FAISS_CUDA_VER:-}" ]; then
    _faiss_latest="$(faiss_installed_cuda_toolkits | tail -1)"
    FAISS_CUDA_VER="${_faiss_latest:-13.2}"  # last-resort fallback if nothing is installed yet
    unset _faiss_latest
fi
export FAISS_CUDA_VER
export FAISS_CUDA_TAG="${FAISS_CUDA_TAG:-cu${FAISS_CUDA_VER//./}}"

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

# gpu_tuned_verify_cuda_compat <path-to-.so> <expected-cuda-ver> — confirms
# a compiled library's NEEDED libcudart.so.<major> matches the CUDA major
# version this build/consumer expects. CUDA's runtime ABI is only
# guaranteed forward-compatible WITHIN a major series (a minor-version
# mismatch, e.g. built against 13.2 but running against 13.3, is fine; a
# MAJOR mismatch, e.g. 12.x vs 13.x, is not) -- so this checks major only,
# by design, not an exact version match. Complements gpu_tuned_verify_arch
# (SM arch) with the orthogonal CUDA-runtime-version axis. Same
# name/signature as zbrad/cuvs's tuned/env.sh equivalent -- used here both
# on faiss's own build output and on the downloaded cuvs release .so (see
# tuned/build.sh's resolve_cuvs_release), since a released cuvs artifact
# could have been built against a different CUDA minor version than the
# one currently active in this environment.
gpu_tuned_verify_cuda_compat() {
    local so_file="$1" expected_cuda_ver="$2"
    if [[ ! -f "${so_file}" ]]; then
        echo "ERROR: gpu_tuned_verify_cuda_compat: no such file: ${so_file}" >&2
        return 1
    fi
    command -v objdump >/dev/null 2>&1 || {
        echo "ERROR: gpu_tuned_verify_cuda_compat: objdump not found on PATH." >&2
        return 1
    }
    local needed found_major expected_major
    needed="$(objdump -p "${so_file}" 2>/dev/null | grep -oE 'libcudart\.so\.[0-9]+' | head -1)"
    if [[ -z "${needed}" ]]; then
        echo "WARNING: ${so_file} has no direct libcudart.so.N NEEDED entry -- skipping CUDA runtime compat check." >&2
        return 0
    fi
    found_major="${needed##*.}"
    expected_major="${expected_cuda_ver%%.*}"
    if [[ "${found_major}" != "${expected_major}" ]]; then
        echo "ERROR: ${so_file} was linked against CUDA runtime major ${found_major}" \
             "(${needed}), but this build expects CUDA ${expected_cuda_ver}" \
             "(major ${expected_major}). CUDA's runtime ABI is only forward-compatible" \
             "within the same major version." >&2
        return 1
    fi
    echo "OK: ${so_file} CUDA runtime compat confirmed (${needed}, matches expected major ${expected_major})"
}

# embed_build_info <so_path> <variant> <package> <version> — embeds a
# greppable build-info string into a custom ELF section (.faiss_build_info)
# on the given .so, readable later via `readelf -p .faiss_build_info <so>`
# or plain `strings`. Safe at runtime: a custom section with no
# program-header entry is simply ignored by the dynamic loader. Same
# technique/name as zbrad/raft's tuned/raft_wheel_common.sh equivalent
# (.raft_build_info).
embed_build_info() {
    local so_path="$1" variant="$2" package="$3" version="$4"
    local tmp
    tmp="$(mktemp)"
    echo "faiss-${variant} build: ${package} v${version}, https://github.com/zbrad/faiss, built $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${tmp}"
    # Idempotent: objcopy --add-section on a section name that already
    # exists (e.g. rebuilding without a clean) empirically corrupts its own
    # in-place rewrite ("file format not recognized" on its own temp
    # output) -- strip any prior stamp first. Same fix as zbrad/cuvs's
    # tuned/env.sh, hit for real running this session's live verification.
    objcopy --remove-section .faiss_build_info "${so_path}" 2>/dev/null || true
    objcopy --add-section .faiss_build_info="${tmp}" "${so_path}"
    rm -f "${tmp}"
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

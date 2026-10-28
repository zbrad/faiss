#!/bin/bash
# tuned/openblas_build.sh <variant> -- build the pinned OpenBLAS as a static, position-independent, OpenMP-threaded
# library with the C LAPACK (no Fortran runtime), so libfaiss links its BLAS and LAPACK statically and the package needs
# no system libopenblas, libblas, liblapack or libgfortran. The result is
# tuned/build/<cuda-tag>/openblas/{lib/libopenblas.a,LICENSE,build-info.txt}. Pin: GPU_TUNED_OPENBLAS_TAG,
# GPU_TUNED_OPENBLAS_SHA and GPU_TUNED_OPENBLAS_TARGET in tuned/repo.env; the tag must resolve to that commit.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "${PROJECT_ROOT}/tuned/env.sh" "$1" || exit 1

OB_SRC="${GPU_TUNED_BUILD_ROOT}/openblas-src"
OB_OUT="${GPU_TUNED_BUILD_ROOT}/openblas"
OB_STAMP="${OB_OUT}/build-info.txt"
WANT="${GPU_TUNED_OPENBLAS_SHA} ${GPU_TUNED_OPENBLAS_TARGET}"

if [[ -f "${OB_OUT}/lib/libopenblas.a" && -f "${OB_STAMP}" ]] && grep -qx "pin=${WANT}" "${OB_STAMP}"; then
    echo "OpenBLAS ${GPU_TUNED_OPENBLAS_TAG} (${GPU_TUNED_OPENBLAS_SHA:0:12}, ${GPU_TUNED_OPENBLAS_TARGET}) already built: ${OB_OUT}/lib/libopenblas.a"
    exit 0
fi

if [[ ! -d "${OB_SRC}/.git" ]]; then
    git clone -q --depth 1 --branch "${GPU_TUNED_OPENBLAS_TAG}" https://github.com/OpenMathLib/OpenBLAS.git "${OB_SRC}" || exit 1
fi
HAVE="$(git -C "${OB_SRC}" rev-parse HEAD)"
[[ "${HAVE}" == "${GPU_TUNED_OPENBLAS_SHA}" ]] \
    || { echo "ERROR: OpenBLAS ${GPU_TUNED_OPENBLAS_TAG} is ${HAVE}, the pin is ${GPU_TUNED_OPENBLAS_SHA}." >&2; exit 1; }

# One core, the variant's (the whole tree is single-arch): DYNAMIC_ARCH=0. NO_FORTRAN=1 selects the C LAPACK.
make -C "${OB_SRC}" clean >/dev/null 2>&1 || true
make -C "${OB_SRC}" -j"$(gpu_tuned_jobs)" \
    TARGET="${GPU_TUNED_OPENBLAS_TARGET}" DYNAMIC_ARCH=0 NO_SHARED=1 USE_OPENMP=1 USE_THREAD=1 NO_FORTRAN=1 \
    NUM_THREADS=128 CFLAGS=-fPIC libs netlib || { echo "ERROR: OpenBLAS build failed" >&2; exit 1; }

rm -rf "${OB_OUT}"
mkdir -p "${OB_OUT}/lib"
LIB="$(ls "${OB_SRC}"/libopenblas*.a | head -1)"
[[ -f "${LIB}" ]] || { echo "ERROR: no libopenblas*.a in ${OB_SRC}" >&2; exit 1; }
cp "${LIB}" "${OB_OUT}/lib/libopenblas.a"
cp "${OB_SRC}/LICENSE" "${OB_OUT}/LICENSE"
{
    echo "openblas=${GPU_TUNED_OPENBLAS_TAG} ${GPU_TUNED_OPENBLAS_SHA}"
    echo "target=${GPU_TUNED_OPENBLAS_TARGET} static openmp c-lapack"
    echo "pin=${WANT}"
} > "${OB_STAMP}"
echo "OpenBLAS ${GPU_TUNED_OPENBLAS_TAG} built: ${OB_OUT}/lib/libopenblas.a"

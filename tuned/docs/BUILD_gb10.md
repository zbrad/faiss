# Building FAISS-GPU Wheel for GB10 / NVIDIA DGX Spark

This guide builds a FAISS-GPU wheel for **aarch64** (ARM), targeting the NVIDIA
DGX Spark — GB10 Grace Blackwell Superchip, compute capability **SM 121**.

Unlike the RTX (x86_64) builds, ARM has **no Intel MKL**: this pipeline uses
a pinned **OpenBLAS** built from source and linked statically for CPU BLAS and LAPACK, and **NVIDIA cuVS** (the `libcuvs-gb10` build from
[zbrad/cuvs](https://github.com/zbrad/cuvs)) for GPU acceleration. See
[BUILD_rtx.md](BUILD_rtx.md) for the RTX 40 / RTX 50 (x86_64) builds.

## Prerequisites

- CUDA 13.2 toolkit for **aarch64 / sbsa-linux** (`/usr/local/cuda-13.2`, or set `CUDA_HOME`)
- Python 3 with development headers, numpy, setuptools
- Build tools: CMake (>=3.24.0), SWIG (4.0), make, a C++20 compiler
- **OpenBLAS**: nothing to install. `tuned/openblas_build.sh` builds the version pinned in `tuned/repo.env` (static, PIC, OpenMP,
  C LAPACK, `TARGET=NEOVERSEV2`) into `tuned/build/<cuda-tag>/openblas/`; `gfortran` is not needed.
- **libcuvs-gb10** built for SM 121 (see next section)
- 8GB+ free disk space

> Intel MKL is **not** used on ARM. If you set `MKL_*` variables they are ignored
> by this pipeline.

## cuVS-gb10 dependency

The GB10 build links the SM 121 cuVS library `libcuvs-gb10-cu132.so`, built
from the [zbrad/cuvs](https://github.com/zbrad/cuvs) fork (GPU-codename naming;
see that repo's `gpu-build/docs/WHEEL_NAMING.md`). Build it first:

```bash
git clone https://github.com/zbrad/cuvs ../cuvs   # a sibling of this faiss checkout
cd ../cuvs && bash tuned/build.sh gb10
# produces cpp/build/libcuvs-gb10-cu132.so
```

(`./build_gb10.sh` still works there too -- it's a deprecation shim for the
consolidated `tuned/build.sh gb10`.)

The build scripts look for it at `${CUVS_DIR}/libcuvs-gb10-${FAISS_CUDA_TAG}.so`,
where `CUVS_DIR` defaults to `${CUVS_REPO}/cpp/build` and `CUVS_REPO` defaults to
`${GITHUB_ROOT}/cuvs`. `GITHUB_ROOT` itself defaults to the parent directory of
this faiss checkout (inferred from this script's own path, not hardcoded), so
things work automatically as long as `cuvs` is cloned as a sibling of `faiss`
under the same parent directory. Override any of the three if your layout
differs:

```bash
export CUVS_REPO=/path/to/cuvs          # or
export CUVS_DIR=/path/to/cuvs/cpp/build
```

## Quick start

```bash
# Full build: C++ lib -> SWIG bindings -> wheel
bash tuned/build.sh gb10
bash tuned/wheel.sh gb10
```

Output wheel lands in `tuned/build/<cuda>/wheel/` (`<cuda>` is the toolkit tag, e.g. `cu134`).
Install and check:

```bash
pip install tuned/build/<cuda>/wheel/faiss_gb10_cu132-*.whl
python -c "import faiss; print(faiss.__version__, faiss.get_num_gpus())"
```

## Build steps

`tuned/build.sh gb10` and `tuned/wheel.sh gb10` consolidate what used to be
four separate scripts (`build_lib_gb10.sh`, `build_pkg_gb10.sh`,
`package_wheel_gb10.sh`, and the `build_wheel_gb10.sh` orchestrator that
called all three):

| Step | What it does |
|------|---------------|
| `tuned/build.sh gb10` | C++ library — SM 121, OpenBLAS, links `libcuvs-gb10-cu132.so`, then `gpu_tuned_verify_arch` confirms the compiled `.so` is really single-arch SM 121 |
| `tuned/wheel.sh gb10` | SWIG bindings (generic opt-level; ARM has no AVX) + wheel packaging + `auditwheel repair` |

## CUDA version selection

The CUDA version is a single input, shared with the RTX pipelines via
`tuned/env.sh`. Specify it per build (the tag is derived):

```bash
FAISS_CUDA_VER=13.3 bash tuned/build.sh gb10   # -> faiss-gb10-cu133
FAISS_CUDA_TAG=cu133 bash tuned/build.sh gb10
```

On a host with multiple toolkits, `CUDA_HOME` auto-resolves to
`/usr/local/cuda-<ver>` (override `CUDA_HOME` to force a path). See
[WHEEL_NAMING.md](WHEEL_NAMING.md) for the full version/naming scheme.

## Outputs

| Artifact | Location | Notes |
|----------|----------|-------|
| `libfaiss-gb10-cu132.so` | `tuned/build/<cuda>/stage/lib/` | Main FAISS GPU library, SM 121 (`FAISS_OUTPUT_NAME`) |
| `libfaiss_c-gb10-cu132.so` | `tuned/build/<cuda>/stage/lib/` | C API wrapper (`FAISS_C_OUTPUT_NAME`) |
| `faiss-gb10-cu132` wheel | `tuned/build/<cuda>/wheel/` | Single-arch wheel, built for the test run only (not published); `manylinux_*_aarch64` platform tag |
| release tarball | `tuned/build/<cuda>/dist/` | Made by `tuned/package.sh`; see [../README.md](../README.md) for the flow |
| links `libcuvs-gb10-cu132.so` | `zbrad/cuvs` build | SM 121 native cuVS |

The `cu132` portion tracks `FAISS_CUDA_TAG`; see [WHEEL_NAMING.md](WHEEL_NAMING.md)
for the full version/naming scheme.

## Troubleshooting

**"libcuvs-gb10-*.so not found"**
- Build it: `cd $CUVS_REPO && bash tuned/build.sh gb10`, or set `CUVS_DIR` to its location.

**OpenBLAS build or link fails**
- `tuned/build/<cuda-tag>/openblas-src` is a clone of the pinned tag; the script refuses a checkout whose commit is not the pin.
  Delete `tuned/build/<cuda-tag>/openblas` to rebuild it.

**"CUDA not found" / version mismatch**
- Ensure the aarch64 CUDA toolkit is installed; `ls $CUDA_HOME/bin/nvcc`
- If `nvcc` reports a different version than `FAISS_CUDA_VER`, set `CUDA_HOME` to the matching toolkit.

**"Python development headers not found"**
- `sudo apt install python3-dev`

**Build runs out of memory**
- Reduce parallelism: `FAISS_BUILD_JOBS=4 bash tuned/build.sh gb10`

## Cleaning up

```bash
bash tuned/clean.sh   # removes cmake/, stage/, python/, test_env/ under each tuned/build/<cuda>/; keeps dist/, wheel/, releases/, ccache/, cuvs/
```

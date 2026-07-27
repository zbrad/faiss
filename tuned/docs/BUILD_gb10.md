# Building FAISS-GPU Wheel for GB10 / NVIDIA DGX Spark

This guide builds a FAISS-GPU wheel for **aarch64** (ARM), targeting the NVIDIA
DGX Spark — GB10 Grace Blackwell Superchip, compute capability **SM 121**.

Unlike the RTX (x86_64) builds, ARM has **no Intel MKL**: this pipeline uses
**OpenBLAS** for CPU BLAS and **NVIDIA cuVS** (the `libcuvs-gb10` build from
[zbrad/cuvs](https://github.com/zbrad/cuvs)) for GPU acceleration. See
[BUILD_rtx.md](BUILD_rtx.md) for the RTX 40 / RTX 50 (x86_64) builds.

## Prerequisites

- CUDA 13.2 toolkit for **aarch64 / sbsa-linux** (`/usr/local/cuda-13.2`, or set `CUDA_HOME`)
- Python 3 with development headers, numpy, setuptools
- Build tools: CMake (>=3.24.0), SWIG (4.0), make, a C++20 compiler
- **OpenBLAS**: `sudo apt install libopenblas-dev` (default `/usr/lib/aarch64-linux-gnu/libopenblas.so`)
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

Output wheel lands in `build_output_gb10/` (and `build_output_gb10/repaired/`
after `auditwheel`). Install and check:

```bash
pip install build_output_gb10/repaired/faiss_gb10_cu132-*.whl
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
| `libfaiss-gb10-cu132.so` | `_libfaiss_stage_gb10/lib/` | Main FAISS GPU library, SM 121 (`FAISS_OUTPUT_NAME`) |
| `libfaiss_c-gb10-cu132.so` | `_libfaiss_stage_gb10/lib/` | C API wrapper (`FAISS_C_OUTPUT_NAME`) |
| `faiss-gb10-cu132` wheel | `build_output_gb10/` | Single-arch wheel; `manylinux_*_aarch64` platform tag |
| links `libcuvs-gb10-cu132.so` | `zbrad/cuvs` build | SM 121 native cuVS |

The `cu132` portion tracks `FAISS_CUDA_TAG`; see [WHEEL_NAMING.md](WHEEL_NAMING.md)
for the full version/naming scheme.

## Troubleshooting

**"libcuvs-gb10-*.so not found"**
- Build it: `cd $CUVS_REPO && bash tuned/build.sh gb10`, or set `CUVS_DIR` to its location.

**"OpenBLAS not found"**
- Install: `sudo apt install libopenblas-dev`
- Non-default path: `export OPENBLAS_LIB=/path/to/libopenblas.so`

**"CUDA not found" / version mismatch**
- Ensure the aarch64 CUDA toolkit is installed; `ls $CUDA_HOME/bin/nvcc`
- If `nvcc` reports a different version than `FAISS_CUDA_VER`, set `CUDA_HOME` to the matching toolkit.

**"Python development headers not found"**
- `sudo apt install python3-dev`

**Build runs out of memory**
- Reduce parallelism: `FAISS_BUILD_JOBS=4 bash tuned/build.sh gb10`

## Cleaning up

```bash
bash tuned/clean.sh   # removes build dirs for all variants
```

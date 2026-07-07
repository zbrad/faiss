# FAISS Wheel Naming Convention

_Last updated: 2026-07-06_

This document records the research and rationale behind the CUDA-versioned
package names used in this branch, and the GPU-codename scheme
(`gb10`/`rtx40`/`rtx50`) they're built on — switched from a single portable
`faiss-gpu-cu132` name to per-codename names (`faiss-rtx40-cu132` etc.) on
2026-07-06, mirroring [zbrad/cuvs](https://github.com/zbrad/cuvs)'s own
GPU-codename convention (see that repo's `gpu-build/docs/WHEEL_NAMING.md`).

---

## Ecosystem Survey

### PyPI

| Package | Status | Latest | Notes |
|---------|--------|--------|-------|
| `faiss-cpu` | **Active** | 1.13.2 | The only actively maintained PyPI FAISS package |
| `faiss-gpu` | **Archived** | 1.7.2 (Jan 2022) | Discontinued — GPU wheels exceed PyPI's 100 MB file size limit |
| `faiss-gpu-cu128` | Does not exist | — | No CUDA-versioned names on PyPI |
| `faiss-gpu-cu132` | Does not exist | — | Same |

GPU wheels were dropped from PyPI as of faiss 1.7.3 and will not return.
The root cause is binary size: a GPU wheel with multiple CUDA architectures
easily exceeds PyPI's upload limit.
See [pypackaging-native.github.io — GPU key issues](https://pypackaging-native.github.io/key-issues/gpus/).

The community-maintained [faiss-wheels](https://github.com/faiss-wheels/faiss-wheels)
project (kyamagu) is the source for `faiss-cpu` on PyPI. Its
`scripts/rename_project.sh faiss-gpu` helper renames the project to `faiss-gpu`
for custom GPU builds, confirming `faiss-gpu` as the de-facto community GPU name
— but **no CUDA-version-specific names** (`-cu128`, `-cu132`) exist or are used.

### Anaconda (pytorch channel)

| Package | Version | Notes |
|---------|---------|-------|
| `faiss-cpu` | 1.14.1 | Active |
| `faiss-gpu` | 1.14.1 | Active, currently built against CUDA 12.6 |
| `faiss-gpu-cuvs` | 1.14.1 | cuVS/RAPIDS variant |
| `faiss-gpu-raft` | 1.9.0 | Older RAPIDS/RAFT variant |

Anaconda uses **feature suffixes** (`-cuvs`, `-raft`) to distinguish build
variants, but **not CUDA version suffixes**. The CUDA version appears only in
the conda package *filename* metadata (e.g. `_cuda12.6_`), not in the package
name itself.

---

## Why CUDA-versioned names?

CUDA-version-specific wheel suffixes (`-cu128`, `-cu132`) originate from
**PyTorch's** distribution convention (e.g. `torch-2.x+cu132`). That convention
has **not** been adopted by the FAISS ecosystem as of 2026-03.

However, it is the right choice for this private branch for several reasons:

1. **No collision risk** — neither PyPI nor Anaconda uses this name, so there is
   no chance of pulling the wrong wheel from a package index.
2. **CUDA runtime is a hard dependency** — a wheel built against CUDA 13.2 will
   not load on a system with a different major CUDA version. Encoding this in the
   name makes the dependency explicit to consumers.
3. **Private / internal distribution** — GPU wheels cannot be published to PyPI
   anyway (size limit). On a private index (Azure Artifacts, Gemfury, DevPI, a
   shared file server) the CUDA version in the name is genuinely useful for
   administrators managing multiple CUDA environments.
4. **Follows an established convention** — PyTorch's `-cu132` suffix is widely
   recognised; users who install PyTorch wheels will find `faiss-rtx40-cu132`
   immediately legible.

---

## CPU arch by platform tag; GPU arch (and CPU arch host once removed) by codename

Two different "architectures" are in play and are encoded differently:

- **CPU arch (x86_64 vs aarch64)** — carried by the wheel's **platform tag**,
  which `auditwheel repair` stamps onto each wheel. Not in the package name.
- **GPU arch (SM / compute capability)** — encoded via **GPU codename**
  (`gb10`/`rtx40`/`rtx50`) rather than a raw SM number, mirroring
  `zbrad/cuvs`'s naming (`libcuvs-gb10-cu132.so` etc.). Every build here is
  single-arch — there is no portable multi-arch wheel anymore, see
  [BUILD_rtx.md](BUILD_rtx.md) for why only owned/verified consumer hardware
  is built.

| Build | Package name | Platform tag (filename) | BLAS / accel |
|-------|--------------|-------------------------|--------------|
| RTX 40 / Ada Lovelace (x86_64, SM 89) | `faiss-rtx40-cu132` | `…-manylinux2014_x86_64.whl` | Intel MKL, AVX2/AVX512 |
| RTX 50 / Blackwell (x86_64, SM 120) | `faiss-rtx50-cu132` | `…-manylinux2014_x86_64.whl` | Intel MKL, AVX2/AVX512 |
| GB10 / DGX Spark (aarch64, always SM 121) | `faiss-gb10-cu132` | `…-manylinux2014_aarch64.whl` | OpenBLAS + cuVS, SVE |

You install the codename matching your GPU explicitly, e.g.
`pip install faiss-rtx40-cu132`.

## `FAISS_VARIANT` Naming Table

The build system exposes a `FAISS_VARIANT` environment variable that is passed
to `setup.py` at wheel-build time. The resulting package name is
`faiss-{FAISS_VARIANT}` (or plain `faiss` when the variable is unset). The
`build_wheel_{gb10,rtx40,rtx50}.sh` scripts each derive
`FAISS_VARIANT={codename}-${FAISS_CUDA_TAG}` directly — no separate `-sm<arch>`
suffix, since the codename alone already implies exactly one arch.

| Scenario | `CUDA_ARCHS` | `FAISS_VARIANT` | Resulting wheel name |
|----------|--------------|-----------------|----------------------|
| CUDA 13.2 GPU, RTX 40 / Ada | `89` | `rtx40-cu132` | `faiss-rtx40-cu132` |
| CUDA 13.2 GPU, RTX 50 / Blackwell | `120` | `rtx50-cu132` | `faiss-rtx50-cu132` |
| CUDA 13.2 GPU, GB10 / DGX Spark | `121` | `gb10-cu132` | `faiss-gb10-cu132` |
| Next CUDA release (`FAISS_CUDA_VER=13.3`) | *(any)* | `{codename}-cu133` | `faiss-{codename}-cu133` |
| CPU-only build | `cpu` | `faiss-cpu` | Exact match for active PyPI package |
| Upstream canonical/untagged | *(unset)* | `faiss` | Plain upstream name |

The Windows/WSL convenience layer (`gpu-cu/wsl/{env,build,verify}_rtx40.sh` /
`_rtx50.sh`) mirrors this same codename scheme and split — see
[the WSL section below](#windows--wsl-convenience-scripts).

## Selecting / bumping the CUDA version (cu132 ↔ cu133)

The CUDA version is a single input. Specify it **per build** (no file edits) with
either variable — the other is derived (`13.3` ⇄ `cu133`):

```bash
FAISS_CUDA_VER=13.3 bash gpu-cu/scripts/build_wheel_rtx40.sh   # RTX 40, CUDA 13.3 → faiss-rtx40-cu133
FAISS_CUDA_VER=13.3 bash gpu-cu/scripts/build_wheel_gb10.sh    # GB10, CUDA 13.3
FAISS_CUDA_TAG=cu133 bash gpu-cu/scripts/build_wheel_rtx50.sh  # tag form
```

To change the **default**, edit the two values in `gpu-cu/scripts/cuda_env.sh`.
Every wheel name (`faiss-{codename}-${FAISS_CUDA_TAG}`) and C++ library name
(`libfaiss-{codename}-${FAISS_CUDA_TAG}.so`) derives from it, so a new CUDA
release needs no script or path renames. The `gpu-cu/` directory and
`environment.yml` are version-agnostic on purpose.

**Multi-toolkit hosts.** When `CUDA_HOME` is not set explicitly, `cuda_env.sh`
resolves it to `/usr/local/cuda-${FAISS_CUDA_VER}` if that directory exists
(falling back to `/usr/local/cuda`). So on a machine with both `cuda-13.2` and
`cuda-13.3` installed, `FAISS_CUDA_VER=13.3` builds against the 13.3 toolkit
automatically. If the `nvcc` found on `PATH` reports a different version than
requested, the scripts print a warning so you can correct `CUDA_HOME`.

---

## Windows / WSL convenience scripts

`gpu-cu/wsl/` mirrors the rtx40/rtx50 split for Windows users building inside
WSL 2:

| Script | Purpose |
|--------|---------|
| `env_rtx40.sh` / `env_rtx50.sh` | Sets `CUDA_ARCHS` (89/120, fixed), `FAISS_VARIANT` (`rtx40-`/`rtx50-${FAISS_CUDA_TAG}`), MKL paths |
| `build_rtx40.sh` / `build_rtx50.sh` | Sources the matching `env_*.sh`, calls `gpu-cu/scripts/build_wheel_rtx40.sh` / `build_wheel_rtx50.sh` directly |
| `verify_rtx40.sh` / `verify_rtx50.sh` | Installs + smoke-tests (CPU and GPU) the built wheel from `build_output_rtx40/` / `build_output_rtx50/` |
| `check_wheel.py [dir]` | Inspects a wheel's bundled `.so` files; defaults to `build_output_rtx40` |

`build_rtx40.sh`/`build_rtx50.sh` used to shell out to `make build`, which
depended on a root `Makefile` target that does not exist in this checkout (a
pre-existing gap, not introduced by this rework) -- fixed to call the real
`build_wheel_{rtx40,rtx50}.sh` scripts directly instead. `FAISS_ROOT` is
inferred from the `env_*.sh` script's own location (no hardcoded drive-letter
guess) -- override it explicitly if you're sourcing a copy of the file from
somewhere other than its normal spot in the checkout. This WSL layer has not
been tested against real Windows/WSL hardware as part of this rework (only
read through for correctness) -- verify it end-to-end before relying on it.

---

## Library Naming Convention (C++ / Shared Object)

When building the C++ libraries directly (without a Python wheel), the following
naming scheme is used. The base names follow CMake target names; the build scripts
append `-{codename}-${FAISS_CUDA_TAG}`. The tables below show the current
`FAISS_CUDA_TAG=cu132`; the `cu132` portion changes with the variable.

### RTX 40 / Ada Lovelace build — `build_lib_rtx40.sh`

| Library | Filename | Notes |
|---------|----------|-------|
| Main C++ library | `libfaiss-rtx40-cu132.so` | `FAISS_OUTPUT_NAME=faiss-rtx40-cu132` |
| AVX2 variant | `libfaiss_avx2.so` | CPU SIMD opt-level (variant names not suffixed) |
| AVX512 variant | `libfaiss_avx512.so` | CPU SIMD opt-level (variant names not suffixed) |
| C API wrapper | `libfaiss_c-rtx40-cu132.so` | `FAISS_C_OUTPUT_NAME=faiss_c-rtx40-cu132` |
| C API AVX2 | `libfaiss_c_avx2.so` | Paired with `libfaiss_avx2` |

> **Note:** `FAISS_OUTPUT_NAME` renames only the base `faiss`/`faiss_c` targets
> (faiss/CMakeLists.txt). The AVX2/AVX512 SIMD variants keep their conventional
> `libfaiss_avx2.so` / `libfaiss_avx512.so` names; `auditwheel` bundles them into
> the wheel regardless of filename.

### RTX 50 / Blackwell build — `build_lib_rtx50.sh`

Same layout as RTX 40, with `rtx50` in place of `rtx40`:
`libfaiss-rtx50-cu132.so`, `libfaiss_c-rtx50-cu132.so`.

### GB10 / DGX Spark (aarch64, SM 121) build — `build_lib_gb10.sh`

| Library | Filename | Notes |
|---------|----------|-------|
| Main C++ library | `libfaiss-gb10-cu132.so` | `FAISS_OUTPUT_NAME=faiss-gb10-cu132` |
| C API wrapper | `libfaiss_c-gb10-cu132.so` | `FAISS_C_OUTPUT_NAME=faiss_c-gb10-cu132` |
| cuVS companion | `libcuvs-gb10-cu132.so` | From `zbrad/cuvs`, SM 121 only |

### GB10 Python wheel — `build_wheel_gb10.sh`

| Artifact | Name | Notes |
|----------|------|-------|
| Python wheel | `faiss-gb10-cu132` | `FAISS_VARIANT=gb10-cu132` in `setup.py` |
| Built by | `build_wheel_gb10.sh` | Orchestrates lib → pkg → wheel steps |
| Stage dir | `_libfaiss_stage_gb10/` | Mirrors `_libfaiss_stage_rtx40/` / `_libfaiss_stage_rtx50/` |

The `FAISS_OUTPUT_NAME` and `FAISS_C_OUTPUT_NAME` cmake variables are defined in
`faiss/CMakeLists.txt` and `c_api/CMakeLists.txt` respectively and have no effect
when left unset (an unconfigured upstream build produces `libfaiss.so` /
`libfaiss_c.so`). The rtx40/rtx50/gb10 build scripts all set them so the three
variants' libraries never collide if installed side by side.

The cuVS companion library name mirrors the zbrad/cuvs project's GPU-codename
convention (switched from a CPU-arch/SM-number scheme on 2026-07-06; see that
repo's `gpu-build/docs/WHEEL_NAMING.md`): `libcuvs-{codename}-{cuda_tag}.so`,
e.g. `libcuvs-gb10-cu132.so` for DGX Spark, `libcuvs-rtx40-cu132.so` /
`libcuvs-rtx50-cu132.so` for the consumer x86_64 builds.

---

## References

- faiss-wheels README: <https://github.com/faiss-wheels/faiss-wheels>
- PyPI `faiss-cpu`: <https://pypi.org/project/faiss-cpu/>
- PyPI `faiss-gpu` (archived): <https://pypi.org/project/faiss-gpu/>
- Anaconda pytorch channel `faiss-gpu`: <https://anaconda.org/pytorch/faiss-gpu>
- GPU packaging background: <https://pypackaging-native.github.io/key-issues/gpus/>
- PyTorch CUDA wheel convention: <https://download.pytorch.org/whl/torch_stable.html>

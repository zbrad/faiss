# faiss 1.15.1 — GB10 / DGX Spark (CUDA 13.4) — v0.20261028.0-gb10-cu134

**Package**: `faiss-0.20261028.0-gb10-cu134.tar.gz` · aarch64 · SM_121a · built and tested at `2064ac60a`, packaged at the commit in `package-info.txt` (only `tuned/` changed in between, which `tuned/package.sh` checks)

**Built against cuVS**: `v0.20261028.0-gb10-cu134`

## Install

The toolkit is part of the release name: `-cu133` is built with CUDA 13.3, `-cu134` with CUDA 13.4. Set `CUDA_TAG` once and
every command below follows it. This note is for **cu134**; to use the cu133 release set `CUDA_TAG=cu133` (it has its own note and tarball).

```
CUDA_TAG=cu134
TAG=v0.20261028.0-gb10-${CUDA_TAG}
# cuVS first (faiss links its libraries; see the cuVS release notes for the commands)
CUVS_PREFIX=~/opt/cuvs-0.20261028.0-gb10-${CUDA_TAG}
PREFIX=~/opt/faiss-0.20261028.0-gb10-${CUDA_TAG}
mkdir -p "${PREFIX}" && cd "${PREFIX}"
gh release download "${TAG}" -R zbrad/faiss -p "faiss-*-gb10-${CUDA_TAG}.tar.gz*"
sha256sum -c faiss-*-gb10-${CUDA_TAG}.tar.gz.sha256
tar xzf faiss-*-gb10-${CUDA_TAG}.tar.gz                   # extracts into the current directory
export LD_LIBRARY_PATH="${PREFIX}/lib:${CUVS_PREFIX}/lib:/usr/local/cuda-13.4/lib64:${LD_LIBRARY_PATH:-}"
```

- **Path:** `~/opt/faiss-0.20261028.0-gb10-cu134/` (`lib/`, `include/`, `share/faiss/`). Extract into a directory of its own.
- **Build against it:** `cmake -Dfaiss_DIR=${PREFIX}/share/faiss ...`.
- **Needs the matching cuVS release** (`v0.20261028.0-gb10-cu134`, which in turn bundles raft): the faiss tarball does not contain the cuVS libraries.
- **Toolkit:** `libfaiss-gb10-cu134.so` has `RUNPATH /usr/local/cuda-13.4/lib64` built in, so it looks for the 13.4 libraries there; a toolkit installed elsewhere needs `LD_LIBRARY_PATH` (which takes precedence), as in the export above.
- **Needs:** aarch64, GB10 (SM 12.1), driver R580 or newer.

## This release

- **No system BLAS or LAPACK.** BLAS and LAPACK are a pinned OpenBLAS (v0.3.34, `e0166008be8e`, `TARGET=NEOVERSEV2`, OpenMP
  threading, C LAPACK) built from source and linked statically into `libfaiss-gb10-cu134.so`. The shipped libraries have no
  `DT_NEEDED` on `libopenblas`, `libblas`, `liblapack` or `libgfortran`, and export no BLAS symbols, so they cannot interpose on
  another BLAS in the same process (`tuned/build.sh` fails otherwise). `libopenblas-dev` is no longer needed to build or run.
  OpenBLAS's license and pin record are in `share/licenses/openblas/`. Earlier releases linked the system `libopenblas`.
- Rebuilt against the new cuVS release, with the build venv's CMake 4 and the tuned-common gates (setuptools 84.2, dependency audit).
- Consumers of the C++ package need **CMake 4.0 or newer** (the cuVS and RMM config files require it).

**Supersedes** `v0.20261019.0-gb10-cu134`, which stays published for consumers that pin its URL.

## Tested

- Full suite (`tuned/full_test.sh`, 2026-10-28): pytest **1368 passed, 248 skipped** (log attached). The CPU paths that use LAPACK
  and BLAS (for example least squares, `SGELSD`) ran on the static OpenBLAS.
- Smoke-tested as packaged: the tarball was extracted and imported; the loaded `libfaiss-gb10-cu134.so` is the package's, and
  72 tests passed, 3 skipped (`test_wheel_smoke_gpu`, `test_index`, `test_clustering`). Not the full suite.

**Not in this release:** the Python wheel (built and dependency-audited, not published).

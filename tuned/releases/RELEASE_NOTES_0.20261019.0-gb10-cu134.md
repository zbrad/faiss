# faiss 1.15 — GB10 / DGX Spark (CUDA 13.4) — v0.20261019.0-gb10-cu134

**Package**: `faiss-0.20261019.0-gb10-cu134.tar.gz` · aarch64 · SM_121a · tested and built at `6a2061c14`, packaged at `50aff8fd0` (only `tuned/` changed in between, which `tuned/package.sh` checks)

## Install

The toolkit is part of the release name: `-cu133` is built with CUDA 13.3, `-cu134` with CUDA 13.4. Set `CUDA_TAG` once and
every command below follows it. This note is for **cu134**; to use the cu133 release set `CUDA_TAG=cu133` (it has its own note and tarball).

```
CUDA_TAG=cu134
TAG=v0.20261019.0-gb10-${CUDA_TAG}
# cuVS first (faiss links its libraries; see the cuVS release notes for the commands)
CUVS_PREFIX=~/opt/cuvs-0.20261019.0-gb10-${CUDA_TAG}
PREFIX=~/opt/faiss-0.20261019.0-gb10-${CUDA_TAG}
mkdir -p "${PREFIX}" && cd "${PREFIX}"
gh release download "${TAG}" -R zbrad/faiss -p "faiss-*-gb10-${CUDA_TAG}.tar.gz*"
sha256sum -c faiss-*-gb10-${CUDA_TAG}.tar.gz.sha256
tar xzf faiss-*-gb10-${CUDA_TAG}.tar.gz                   # extracts into the current directory
export LD_LIBRARY_PATH="${PREFIX}/lib:${CUVS_PREFIX}/lib:/usr/local/cuda-13.4/lib64:${LD_LIBRARY_PATH:-}"
```

- **Path:** `~/opt/faiss-0.20261019.0-gb10-cu134/` (`lib/`, `include/`, `share/faiss/`). Extract into a directory of its own.
- **Build against it:** `cmake -Dfaiss_DIR=${PREFIX}/share/faiss ...`.
- **Needs the matching cuVS release** (`v0.20261019.0-gb10-cu134`, which in turn bundles raft): the faiss tarball does not contain the cuVS libraries.
- **Toolkit:** `libfaiss-gb10-cu134.so` has `RUNPATH /usr/local/cuda-13.4/lib64` built in, so it looks for the 13.4 libraries there; a toolkit installed elsewhere needs `LD_LIBRARY_PATH` (which takes precedence), as in the export above.
- **Needs:** aarch64, GB10 (SM 12.1), driver R580 or newer.

## Components

| Component | Shipped file | Device code | Tests | Result |
|---|---|---|---|---|
| faiss 1.15 | `libfaiss-gb10-cu134.so`, `libfaiss_c-gb10-cu134.so` | yes (sm_121a) | pytest `tests/` minus `external_module_test.py` | 1,369 passed, 247 skipped, 800 subtests passed |
| cuVS and chain (not shipped) | from cuVS `v0.20261019.0-gb10-cu134` | yes | used by the faiss tests and smoke | passed |
| Package as extracted | `faiss-0.20261019.0-gb10-cu134.tar.gz` | | smoke: `test_wheel_smoke_gpu`, `test_index`, `test_clustering` | 72 passed, 3 skipped, 8 subtests passed |

## This release

`libfaiss-gb10-cu134.so` and `libfaiss_c-gb10-cu134.so` (device code: variant and toolkit), built in the flat per-toolkit tree against cuVS
`v0.20261019.0-gb10-cu134`. The library names are unchanged from the earlier release; what changes is the cuVS chain underneath
(`libcuvs-gb10-cu134.so`, `librmm-cu134.so`, `librapids_logger-cu134.so`, `libkvikio-cu134.so`). **Requires that cuVS release** (publish raft, then cuVS, first).

**Supersedes** `v0.20261015.0-gb10-cu134`, which carries the earlier `-tuned` shared-object names and stays published for consumers that pin its URL.

## Tested

- pytest (`tests/`, minus `tests/external_module_test.py`): **1,369 passed, 247 skipped, 800 subtests passed** (log attached).
- Smoke-tested as packaged: the tarball extracted on its own; `_swigfaiss.so` resolves `libfaiss-gb10-cu134.so` inside the package; an import maps 20 libraries, none from the build stage;
  `test_wheel_smoke_gpu`, `test_index`, `test_clustering`: 72 passed, 3 skipped, 8 subtests passed (log attached). Three files, not the suite.

**Not in this release:** the Python wheel (built for the test run, not published).

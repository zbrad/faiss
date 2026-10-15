# faiss 1.15 — GB10 / DGX Spark Release Notes (CUDA 13.3)

**Release**: `v0.20261015.0-gb10-cu133` (2026-10-15)
**Package**: `faiss-0.20261015.0-gb10-cu133.tar.gz`
**Platform**: aarch64
**GPU Architecture**: SM_121a (GB10 / DGX Spark, Grace Blackwell)
**Re-release of**: `v1.15-gb10-cu133-g48ca87794`

## This release

`libfaiss-gb10-cu133.so` 1.15 (install tree: `lib/`, `include/`), single-arch, linked against the `-tuned` cuVS chain
(`libcuvs-gb10-cu133.so`, `librmm-tuned.so`, `librapids_logger-tuned.so`, `libkvikio-tuned.so`). The same library as
`v1.15-gb10-cu133-g48ca87794`, published under the fleet's date-label tag (`v0.<UTC date>.<seq>-<variant>-<cuda>`, tuned-common
`docs/ARCHITECTURE.md` E2) instead of `v<upstream version>-<variant>-<cuda>-g<sha>`. Nothing in the library changed:
it was repackaged from the existing build (tested at `48ca87794`; no source outside `tuned/` has changed since, which
`tuned/package.sh` now checks), not rebuilt. The old tag is superseded by this one.

**cuVS:** built against `v26.12-gb10-cu133-g1f3c58b6`; cuVS has since been re-released as
[`v0.20261015.0-gb10-cu133`](https://github.com/zbrad/cuvs/releases/tag/v0.20261015.0-gb10-cu133), the same package under the date-label name, so that is the
cuVS for this faiss. `tuned/build.sh` now takes the newest date-label cuVS release.

**Tested:** the pytest suite (`tests/`, minus `tests/external_module_test.py`, which needs a separately built example module)
passed on this build: 1,369 passed, 247 skipped, 800 subtests passed (log attached). **Smoke-tested as packaged:** the tarball
was extracted and checked on its own: its sha256 against `package-info.txt`, the wheel's `_swigfaiss.so` resolving
`libfaiss-gb10-cu133.so` to a file inside the package, an import in a clean interpreter mapping `libfaiss-gb10-cu133.so` from the package
and the cuVS libraries from the cuVS release (none from the build stage), and `tests/test_wheel_smoke_gpu.py`, `tests/test_index.py`
and `tests/test_clustering.py` (72 passed, 3 skipped, 8 subtests passed) run in that environment (log attached). The smoke run is three test
files, not the suite.

**Not in this release:** the Python wheel (`tuned/wheel.sh` builds it for the test run; it is not published).

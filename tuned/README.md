# tuned/ — GPU-tuned faiss builds

Per-variant builds of faiss (`gb10`, `rtx40`, `rtx50`) against one CUDA toolkit. Every script takes the variant
as its argument and sources `env.sh`, which selects the toolkit (`FAISS_CUDA_VER=13.4` or `FAISS_CUDA_TAG=cu134`)
and refuses to guess one.

## Flow

Stages run in this order; each gate in the later stages refuses to run on a stale earlier stage.

| Stage | Command | Output |
|-------|---------|--------|
| 1. build | `bash tuned/build.sh <variant>` | `tuned/build/<cuda>/cmake/`, `stage/` (the staged install). Downloads the matching zbrad/cuvs release into `cuvs/` |
| 1b. wheel | `bash tuned/wheel.sh <variant>` | `tuned/build/<cuda>/wheel/`. Built for the test run only; not published |
| 2. full test | `bash tuned/full_test.sh <variant>` | `tuned/build/<cuda>/releases/TEST_RESULTS_<variant>.log`, ending in `Full test suite summary` |
| 3. package | `bash tuned/package.sh <variant>` | `tuned/build/<cuda>/dist/` tarball, `.sha256`, `package-info.txt`. Allocates the release label. Writes a DRAFT `tuned/releases/RELEASE_NOTES_<label>.md` if none exists |
| 4. smoke test | `bash tuned/smoke_test.sh <variant>` | `tuned/build/<cuda>/releases/SMOKE_RESULTS_<variant>.log`, from the tarball as extracted |
| 5. notes | edit `tuned/releases/RELEASE_NOTES_<label>.md`, delete its DRAFT line, commit it | a tracked, reviewed notes file |
| 6. release | `bash tuned/release.sh <variant>` | Runs the gates only; never publishes. If all pass, writes `tuned/build/<cuda>/releases/RELEASE_READY_<variant>` (the ready-marker) |
| 7. publish | `bash tuned/publish.sh <variant>` | Publishes the GitHub release (tarball, sidecar, notes, test and smoke logs) from the ready-marker only; refuses if HEAD, the notes or an asset changed since release.sh passed |

`tuned/clean.sh` removes the rebuildable parts of each `tuned/build/<cuda>/` tree and the old-layout leftovers.
It keeps `dist/`, `wheel/`, `releases/`, `ccache/` and `cuvs/`.

## Other files

- `common-data/`, `common.sh`: vendored from tuned-common; refresh with `sync-common.sh`, do not hand-edit.
- `repo.env`: faiss's own build settings (BLAS, SIMD level, SWIG and make targets).
- `verify_environment.py`: checks the wheel build environment for the target CUDA version.
- `compliance.conf` (when tracked): read by tuned-common's `tools/tuned_compliance.sh`.

Layout and naming rules are in tuned-common's `docs/ARCHITECTURE.md`.

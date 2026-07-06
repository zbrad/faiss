# Building FAISS-GPU Wheel for RTX 40 / RTX 50 (CUDA 13.2, Python 3.14)

This guide builds a FAISS-GPU wheel for consumer x86_64 GPUs, as two separate
single-arch builds by generation:

- **RTX 40** (Ada Lovelace, SM 89) — RTX 4080, RTX 4090 — `build_wheel_rtx40.sh`
- **RTX 50** (Blackwell, SM 120) — RTX 5080, RTX 5090 — `build_wheel_rtx50.sh`

This mirrors [zbrad/cuvs](https://github.com/zbrad/cuvs)'s own `build_rtx40.sh`
/ `build_rtx50.sh` split, which dropped datacenter/professional architectures
(Hopper, Blackwell DC, GB200, Ada professional parts) from its build matrix for
the same reason: only build what's actually owned/verified. See
[BUILD_gb10.md](BUILD_gb10.md) for the aarch64 / DGX Spark build.

## Quick start (WSL on Windows)

The fastest path on Windows is WSL 2 (Ubuntu). One-time Intel oneAPI MKL install
inside WSL:

```bash
wget -qO - https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
  | sudo gpg --dearmor -o /usr/share/keyrings/intel-sw-products.gpg
echo "deb [signed-by=/usr/share/keyrings/intel-sw-products.gpg] https://apt.repos.intel.com/oneapi all main" \
  | sudo tee /etc/apt/sources.list.d/oneAPI.list
sudo apt update && sudo apt install -y intel-oneapi-mkl-devel
```

Then build and verify (from PowerShell or inside WSL) — pick the pair
matching your GPU generation:

```powershell
wsl -e bash gpu-cu/wsl/build_rtx40.sh             # RTX 4080/4090
wsl -e bash gpu-cu/wsl/verify_rtx40.sh --install  # install wheel + CPU/GPU sanity check

wsl -e bash gpu-cu/wsl/build_rtx50.sh             # RTX 5080/5090
wsl -e bash gpu-cu/wsl/verify_rtx50.sh --install
```

`gpu-cu/wsl/env_rtx40.sh` / `env_rtx50.sh` set the WSL build environment
(sourced automatically by the matching `build_*.sh`). Override the CUDA
version per invocation:

```bash
FAISS_CUDA_VER=13.3 source gpu-cu/wsl/env_rtx40.sh
```

The rest of this guide covers the general (non-WSL) build and options.

## Prerequisites

- CUDA 13.2 toolkit installed
- Python 3.14
- Build tools: CMake (>=3.24.0), SWIG (4.0), make, C++20 compiler
- Dependencies: Intel MKL, numpy, setuptools
- 8GB+ free disk space for build

## Quick Setup

### Option 1: Using Conda (Recommended)

```bash
# Create a conda environment with required dependencies
conda create -n faiss-gpu-cu132-py314 \
  -c pytorch \
  -c nvidia \
  -c conda-forge \
  python=3.14 \
  cmake>=3.24.0 \
  swig=4.0 \
  make=4.2 \
  cuda-toolkit=13.2 \
  mkl-devel>=2024.2.2 \
  gcc=12.4 \
  numpy \
  setuptools

conda activate faiss-gpu-cu132-py314
```

### Option 2: System Installation

Ensure the following are installed on your system:
- CUDA 13.2: `/usr/local/cuda-13.2` (or set `CUDA_HOME` variable)
- Python 3.14 with development headers
- CMake >= 3.24.0
- Intel MKL development libraries
- GCC 12.4+ with C++20 support

## Build Instructions

### 1. Set Environment Variables

```bash
export CUDA_HOME=/usr/local/cuda-13.2  # Adjust if using different path
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
```

`CUDA_ARCHS` is fixed per script now (`89` in `build_lib_rtx40.sh`, `120` in
`build_lib_rtx50.sh`) rather than an overridable multi-arch list — pick the
script matching your GPU generation instead of setting `CUDA_ARCHS`.

### 1.1 Set Intel MKL Paths (Required)

`gpu-cu/scripts/build_lib_rtx40.sh` / `build_lib_rtx50.sh` require Intel MKL (`mkl_rt`) and may need explicit paths when auto-detection does not match your shell environment.

**WSL/Linux bash accessing Windows oneAPI install:**
```bash
export MKL_ROOT="/mnt/c/Program Files (x86)/Intel/oneAPI/mkl/2025.3"
export MKL_LIB="$MKL_ROOT/lib/mkl_rt.lib"
export MKL_INCLUDE_DIR="$MKL_ROOT/include"
ls -l "$MKL_LIB" "$MKL_INCLUDE_DIR/mkl.h"
```

**Git Bash on Windows (MSYS path style):**
```bash
export MKL_ROOT="/c/Program Files (x86)/Intel/oneAPI/mkl/2025.3"
export MKL_LIB="$MKL_ROOT/lib/mkl_rt.lib"
export MKL_INCLUDE_DIR="$MKL_ROOT/include"
ls -l "$MKL_LIB" "$MKL_INCLUDE_DIR/mkl.h"
```

**Find your exact installed MKL runtime from CMD:**
```cmd
where /r "C:\Program Files (x86)\Intel\oneAPI\mkl" mkl_rt*
```

Use the versioned MKL directory (for example `.../mkl/2025.3`) if `latest` symlink/path resolution behaves differently between shells.

Supported GPU architectures (CUDA 13.2):
- `89`: Ada Lovelace (RTX 4090, RTX 4080) — `build_lib_rtx40.sh`
- `120`: Blackwell (RTX 5090, RTX 5080) — `build_lib_rtx50.sh`
- `121`: Blackwell (GB10 Grace Blackwell / DGX Spark, aarch64) — see [BUILD_gb10.md](BUILD_gb10.md)

Datacenter/professional architectures (Turing, Ampere, Hopper, Blackwell DC,
GB200, Ada professional parts like L40/L40S/RTX 6000 Ada) are intentionally
**not** built here — see [WHEEL_NAMING.md](WHEEL_NAMING.md) for the rationale.

### 2. Build the Wheel

Use one of the provided build scripts:

**Automated build (recommended):**
```bash
bash gpu-cu/scripts/build_wheel_rtx40.sh   # RTX 4080/4090
# or
bash gpu-cu/scripts/build_wheel_rtx50.sh   # RTX 5080/5090
```

**Manual build:**
```bash
# Step 1: Build the C++ library
bash gpu-cu/scripts/build_lib_rtx40.sh     # or build_lib_rtx50.sh

# Step 2: Build Python bindings and wheel
bash gpu-cu/scripts/build_pkg_rtx40.sh     # or build_pkg_rtx50.sh
```

### 3. Find the Built Wheel

The wheel will be located in `build_output_rtx40/` (or `build_output_rtx50/`):
```bash
ls -lh build_output_rtx40/faiss_rtx40*.whl
```

## Installation

To install the built wheel:

```bash
pip install build_output_rtx40/faiss_rtx40-*.whl
```

Verify installation:
```bash
python -c "import faiss; print(faiss.__version__); print(faiss.gpuGetNumDevices())"
```

## More options

- **Optimization Level**:
  - `generic`: Baseline optimization
  - `avx2`: AVX2 SIMD optimizations (default)
  - `avx512`: AVX512 optimizations
  - `avx512_spr`: Intel Sapphire Rapids optimizations

- **Build Type**: Add `-DCMAKE_BUILD_TYPE=Debug` for debug symbols

## Troubleshooting

**"CUDA not found"**
- Ensure CUDA 13.2 is installed and `CUDA_HOME` is set correctly
- Check: `ls $CUDA_HOME/bin/nvcc`

**"nvcc architecture mismatch"**
- List available architectures: `nvidia-smi --query-gpu=compute_cap --format=csv,noheader --format=csv`
- Confirm it matches the script you're running (89 for rtx40, 120 for rtx50)

**"Python development headers not found"**
- Install: `sudo apt install python3.14-dev` (or equivalent for your system)
- Or use conda environment with python-dev package

**"Build runs out of memory"**
- Reduce parallel jobs: `FAISS_BUILD_JOBS=4 bash gpu-cu/scripts/build_wheel_rtx40.sh`

**"swig: command not found"**
- Install: `conda install swig=4.0` or `sudo apt install swig`

**"MKL runtime library not found"**
- Verify the shell path style matches your environment:
  - WSL/Linux bash: `/mnt/c/...`
  - Git Bash: `/c/...`
- Confirm files exist: `mkl_rt.lib` and `include/mkl.h`
- Use a versioned MKL path (e.g. `.../mkl/2025.3`) instead of `latest` if needed

## Performance Notes

- First build takes 10-30 minutes depending on machine
- Subsequent builds use CMake cache for faster incremental builds
- Wheel size: ~300-500MB (includes GPU kernels)

## Testing the Wheel

```bash
# Run FAISS tests
python -c "from faiss import gpu; gpu.StandardGpuResources()"

# Run benchmarks
cd benchs/
python bench_*.py
```

## Cleaning Up

```bash
# Remove build files but keep wheel
bash gpu-cu/scripts/clean_build.sh

# Remove everything including wheels
rm -rf build/ _build* _libfaiss_stage* build_output*/
```

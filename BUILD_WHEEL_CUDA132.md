# Building FAISS-GPU Wheel for CUDA 13.2 and Python 3.14

This guide walks through building a FAISS-GPU wheel for CUDA 13.2 targeting Python 3.14.

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
export CUDA_ARCHS="80;86;89;90;92"  # Adjust for your GPU architectures
```

Available CUDA architectures (CUDA 13.2 supported):
- `80`: Ampere (A100, RTX 3090)
- `86`: Ampere (RTX 3080 Ti, RTX 3070)
- `89`: Ada Lovelace (RTX 4090, RTX 4080)
- `90`: Hopper (H100)
- `92`: Blackwell (RTX 5090, GB10 / DGX Spark)

> **Note:** Volta (70) and Turing (75) are **not supported** in CUDA 13.2 — NVIDIA removed
> offline compilation and library support in CUDA 13.0. For older GPUs, use CUDA 12.x.
> See: [CUDA 13.2 Release Notes - Deprecated Architectures](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html#deprecated-architectures)

### 2. Build the Wheel

Use one of the provided build scripts:

**Automated build (recommended):**
```bash
bash build_wheel_cuda132.sh
```

**Manual build:**
```bash
# Step 1: Build the C++ library
bash build_lib_cuda132.sh

# Step 2: Build Python bindings and wheel
bash build_pkg_cuda132.sh
```

### 3. Find the Built Wheel

The wheel will be located in `build_output/` directory:
```bash
ls -lh build_output/faiss_gpu*.whl
```

## Installation

To install the built wheel:

```bash
pip install build_output/faiss_gpu-*.whl
```

Verify installation:
```bash
python -c "import faiss; print(faiss.__version__); print(faiss.gpuGetNumDevices())"
```

## Customization Options

During build, you can customize:

- **GPU Architectures**: Set `CUDA_ARCHS` environment variable (space/semicolon separated)
  - Examples:
    - `CUDA_ARCHS="92"` - RTX 5090 (Blackwell) only
    - `CUDA_ARCHS="90"` - H100 (Hopper) only  
    - `CUDA_ARCHS="90;92"` - Hopper + Blackwell
    - `CUDA_ARCHS="80;86;89;90;92"` - All supported (default)

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
- Convert to CUDA_ARCHS format (e.g., 8.0 → 80)

**"Python development headers not found"**
- Install: `sudo apt install python3.14-dev` (or equivalent for your system)
- Or use conda environment with python-dev package

**"Build runs out of memory"**
- Reduce parallel jobs: `make -j4` instead of `-j$(nproc)`
- Edit build scripts and change `$(nproc)` to desired number

**"swig: command not found"**
- Install: `conda install swig=4.0` or `sudo apt install swig`

## Performance Notes

- First build takes 10-30 minutes depending on GPU count and machine
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
bash clean_build.sh

# Remove everything including wheels
rm -rf build/ _build* _libfaiss_stage/ build_output/
```

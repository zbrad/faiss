# FAISS-GPU CUDA 13.2 Wheel Builder

Quick start guide for building FAISS-GPU wheel for CUDA 13.2 with Python 3.14.

## ⚡ Quick Start (5 minutes)

### 1. Set Up Environment

```bash
# Using Conda (Recommended)
conda env create -f environment_cuda132_py314.yml
conda activate faiss-gpu-cu132-py314

# OR manually install prerequisites
# ensure: python 3.14, CUDA 13.2, cmake, swig, mkl-devel
```

### 1.1 Configure Intel MKL Paths (Required for `build_lib_cuda132.sh`)

If MKL auto-detection does not work, set explicit paths before building.

```bash
# WSL / Linux-style bash (Windows oneAPI install mounted at /mnt/c)
export MKL_ROOT="/mnt/c/Program Files (x86)/Intel/oneAPI/mkl/2025.3"
export MKL_LIB="$MKL_ROOT/lib/mkl_rt.lib"
export MKL_INCLUDE_DIR="$MKL_ROOT/include"
ls -l "$MKL_LIB" "$MKL_INCLUDE_DIR/mkl.h"
```

```bash
# Git Bash on Windows (MSYS path style)
export MKL_ROOT="/c/Program Files (x86)/Intel/oneAPI/mkl/2025.3"
export MKL_LIB="$MKL_ROOT/lib/mkl_rt.lib"
export MKL_INCLUDE_DIR="$MKL_ROOT/include"
ls -l "$MKL_LIB" "$MKL_INCLUDE_DIR/mkl.h"
```

Find installed MKL runtime from `cmd`:

```cmd
where /r "C:\Program Files (x86)\Intel\oneAPI\mkl" mkl_rt*
```

### 2. Build the Wheel

```bash
# Full build (library + python package + wheel)
./build_wheel.sh all

# Or individual steps:
./build_wheel.sh lib      # C++ library only
./build_wheel.sh pkg      # Library + Python package
./build_wheel.sh wheel    # Complete wheel
```

### 3. Install & Test

```bash
# Install the wheel
pip install build_output/faiss_gpu*.whl

# Verify installation
python -c "import faiss; print(f'FAISS version: {faiss.__version__}'); print(f'GPU devices: {faiss.gpuGetNumDevices()}')"
```

## 📋 Available Scripts

| Script | Purpose |
|--------|---------|
| `build_wheel.sh` | Main unified builder (recommended) |
| `build_lib_cuda132.sh` | Build C++ library only |
| `build_pkg_cuda132.sh` | Build Python package |
| `package_wheel.sh` | Create .whl package |
| `clean_build.sh` | Remove build artifacts |

## 🔧 Common Commands

```bash
# Check if prerequisites are installed
./build_wheel.sh check

# Build for Hopper (H100) only
CUDA_ARCHS="90" ./build_wheel.sh

# Build for Blackwell (RTX 5090) only
CUDA_ARCHS="120" ./build_wheel.sh

# Build for DGX Spark (GB10 Blackwell) only
CUDA_ARCHS="100" ./build_wheel.sh

# Build for Hopper + Blackwell (H100, RTX 5090, DGX Spark)
CUDA_ARCHS="90;100;120" ./build_wheel.sh

# Build for RTX 4090 (Ada)
CUDA_ARCHS="89" ./build_wheel.sh

# Build with more parallel jobs
FAISS_BUILD_JOBS=16 ./build_wheel.sh

# Clean up and rebuild
./clean_build.sh
./build_wheel.sh
```

## 📊 GPU Architecture Codes

Set `CUDA_ARCHS` environment variable before building:

| Architecture | GPU Examples |
|-------------|--------------|
| `75` | RTX 2080, RTX 2060 (Turing) |
| `80` | A100, RTX 3090 (Ampere) |
| `86` | RTX 3080 Ti, RTX 3070 (Ampere) |
| `89` | RTX 4090, RTX 4080 (Ada) |
| `90` | H100 (Hopper) |
| `100` | GB10 Grace Blackwell (DGX Spark) |
| `120` | RTX 5090 (Blackwell) |

```bash
# Build for multiple architectures
CUDA_ARCHS="75;80;86;89;90;100;120" ./build_wheel.sh
```

## 📁 Directory Structure After Build

```
faiss-gpu-cu132/
├── build_output/         # Output wheels
│   └── faiss_gpu-*.whl
├── _build/               # C++ build artifacts
├── _build_python_*/      # Python build artifacts
├── _libfaiss_stage/      # Staged libraries
└── [source files]
```

## 🐛 Troubleshooting

**CUDA not found:**
```bash
export CUDA_HOME=/usr/local/cuda-13.2
export PATH=$CUDA_HOME/bin:$PATH
```

**Python dev headers missing:**
```bash
# Conda users
conda install python-devel

# System users
sudo apt install python3.14-dev
```

**"make: parallel limits exceeded":**
```bash
# Reduce parallel jobs
FAISS_BUILD_JOBS=4 ./build_wheel.sh
```

**Memory issues during build:**
- Close other applications
- Use: `FAISS_BUILD_JOBS=2 ./build_wheel.sh`

**"MKL runtime library not found":**
- Ensure shell path style matches environment:
	- WSL/Linux bash: `/mnt/c/...`
	- Git Bash: `/c/...`
- Confirm both files exist:
	- `$MKL_LIB`
	- `$MKL_INCLUDE_DIR/mkl.h`
- Prefer versioned MKL path (`.../mkl/2025.3`) if `latest` path/symlink is not resolved

## 📖 Full Documentation

See [BUILD_WHEEL_CUDA132.md](BUILD_WHEEL_CUDA132.md) for complete documentation.

## 📝 Notes

- First build takes 10-30 minutes
- Uses AVX2 optimization by default
- Wheel size: ~300-500MB
- Requires 8GB+ free disk space

## ✅ Testing

```bash
# Quick sanity check
python -c "from faiss import gpu; gpu.StandardGpuResources()"

# Run full test suite
python -m pytest tests/

# Run GPU tests
cd faiss/gpu/test && python -m pytest test_*.py
```

## 📦 Wheel Details

The built wheel includes:
- FAISS Python bindings (faiss.py module)
- GPU index implementations
- CUDA kernels for supported architectures
- C API bindings
- Optimized SIMD variants (AVX2, AVX512)

## 🔗 Resources

- **Official Repo:** https://github.com/facebookresearch/faiss
- **Documentation:** https://github.com/facebookresearch/faiss/wiki
- **Issue Tracker:** https://github.com/facebookresearch/faiss/issues
- **Build Guide:** [BUILD_WHEEL_CUDA132.md](BUILD_WHEEL_CUDA132.md)

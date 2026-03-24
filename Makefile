.PHONY: help check build build-lib build-pkg wheel clean env-create env-info test

# FAISS GPU Wheel Build Makefile for CUDA 13.2

CUDA_ARCHS ?= 80;86;89;90
CUDA_HOME ?= /usr/local/cuda
FAISS_BUILD_JOBS ?= $(shell nproc)
PYTHON ?= python3

help:
	@echo "FAISS GPU Wheel Build (CUDA 13.2)"
	@echo ""
	@echo "Targets:"
	@echo "  make build             - Full build (lib + pkg + wheel)"
	@echo "  make build-lib         - Build C++ library only"
	@echo "  make build-pkg         - Build library and Python package"
	@echo "  make wheel             - Package wheel"
	@echo "  make check             - Check prerequisites"
	@echo "  make clean             - Remove build artifacts"
	@echo "  make env-create        - Create conda environment"
	@echo "  make env-info          - Show build configuration"
	@echo "  make test              - Run tests"
	@echo ""
	@echo "Environment Variables:"
	@echo "  CUDA_ARCHS             - GPU architectures (default: 80;86;89;90;92)"
	@echo "  CUDA_HOME              - CUDA installation path"
	@echo "  FAISS_BUILD_JOBS       - Parallel build jobs"
	@echo "  PYTHON                 - Python executable"

build: build-lib build-pkg wheel
	@echo "✓ Full build complete"
	@ls -lh build_output/*.whl 2>/dev/null || echo "No wheel found"

build-lib:
	@export CUDA_ARCHS=$(CUDA_ARCHS); \
	export CUDA_HOME=$(CUDA_HOME); \
	export FAISS_BUILD_JOBS=$(FAISS_BUILD_JOBS); \
	export PYTHON=$(PYTHON); \
	bash build_lib_cuda132.sh

build-pkg: build-lib
	@export CUDA_HOME=$(CUDA_HOME); \
	export FAISS_BUILD_JOBS=$(FAISS_BUILD_JOBS); \
	export PYTHON=$(PYTHON); \
	bash build_pkg_cuda132.sh

wheel: build-pkg
	@export PYTHON=$(PYTHON); \
	bash package_wheel.sh

check:
	@export CUDA_ARCHS=$(CUDA_ARCHS); \
	export CUDA_HOME=$(CUDA_HOME); \
	export PYTHON=$(PYTHON); \
	bash build_wheel.sh check

clean:
	@bash clean_build.sh

env-create:
	@echo "Creating conda environment: faiss-gpu-cu132-py314"
	conda env create -f environment_cuda132_py314.yml
	@echo ""
	@echo "To activate, run:"
	@echo "  conda activate faiss-gpu-cu132-py314"

env-info:
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Build Configuration"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  CUDA_ARCHS:        $(CUDA_ARCHS)"
	@echo "  CUDA_HOME:         $(CUDA_HOME)"
	@echo "  FAISS_BUILD_JOBS:  $(FAISS_BUILD_JOBS)"
	@echo "  PYTHON:            $(PYTHON)"
	@echo "  Python version:    $$($(PYTHON) --version 2>&1)"
	@echo ""
	@echo "  GPU architectures:"
	@echo "    70 = Tesla V100"
	@echo "    75 = RTX 2080, RTX 2060"
	@echo "    80 = A100, RTX 3090"
	@echo "    86 = RTX 3080 Ti, RTX 3070"
	@echo "    89 = RTX 4090, RTX 4080"
	@echo "    90 = H100 (Hopper)"
	@echo "    92 = RTX 5090 (Blackwell)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test:
	@export PYTHONPATH=$$(find . -path ./build_output -prune -o -name "build/lib*" -type d -print); \
	echo "Running FAISS tests..."; \
	$(PYTHON) -m pytest tests/ -v 2>/dev/null || echo "pytest not found. Install with: pip install pytest"

install-wheel:
	@wheel=$$(ls -t build_output/faiss_gpu*.whl 2>/dev/null | head -1); \
	if [ -z "$$wheel" ]; then \
		echo "ERROR: No wheel found in build_output/"; \
		exit 1; \
	fi; \
	echo "Installing $$wheel"; \
	$(PYTHON) -m pip install "$$wheel"
	@echo "Verifying installation..."; \
	$(PYTHON) -c "import faiss; print('✓ FAISS installed'); print('  Version:', faiss.__version__); print('  GPU devices:', faiss.gpuGetNumDevices())"

# Convenient shorthand targets
.PHONY: lib pkg all
lib: build-lib
pkg: build-pkg
all: build

# Phony targets
.PHONY: clean help build build-lib build-pkg wheel check env-create env-info test

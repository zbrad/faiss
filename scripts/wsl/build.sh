#!/bin/bash
# Full WSL build: C++ library + Python SWIG bindings + wheel
# Usage (from PowerShell):
#   wsl -e bash scripts/wsl/build.sh
# Optional env overrides:
#   CUDA_ARCHS="75;80;86"  wsl -e bash scripts/wsl/build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

cd "$FAISS_ROOT"

# Strip any Windows CRLF from build scripts (safe to run each time)
sed -i 's/\r//' build_lib_cuda132.sh build_pkg_cuda132.sh package_wheel.sh Makefile wsl_build.sh 2>/dev/null || true

echo ""
echo "========================================="
echo " FAISS GPU CUDA 13.2 — Full Build"
echo "========================================="
echo " Architectures : $CUDA_ARCHS"
echo " Jobs          : $(nproc)"
echo " Log           : /tmp/faiss_build.log"
echo "========================================="
echo ""

make build 2>&1 | tee /tmp/faiss_build.log

echo ""
echo "Build log saved to /tmp/faiss_build.log"

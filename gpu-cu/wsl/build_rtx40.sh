#!/bin/bash
# Full WSL build: C++ library + Python SWIG bindings + wheel — RTX 40 / Ada Lovelace
# Usage (from PowerShell):
#   wsl -e bash gpu-cu/wsl/build_rtx40.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env_rtx40.sh"

cd "$FAISS_ROOT"

# Strip any Windows CRLF from build scripts (safe to run each time)
sed -i 's/\r//' gpu-cu/scripts/*.sh 2>/dev/null || true

echo ""
echo "========================================="
echo " FAISS GPU CUDA $FAISS_CUDA_VER — RTX 40 Build"
echo "========================================="
echo " Architecture  : $CUDA_ARCHS (Ada Lovelace, RTX 4080/4090)"
echo " Jobs          : $(nproc)"
echo " Log           : /tmp/faiss_build_rtx40.log"
echo "========================================="
echo ""

bash gpu-cu/scripts/build_wheel_rtx40.sh 2>&1 | tee /tmp/faiss_build_rtx40.log

echo ""
echo "Build log saved to /tmp/faiss_build_rtx40.log"

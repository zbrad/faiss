#!/bin/bash
# tuned/wsl/build.sh <variant> — full WSL build: C++ library + Python SWIG
# bindings + wheel (rtx40/rtx50 only). Usage (from PowerShell):
#   wsl -e bash tuned/wsl/build.sh rtx50
#
# Consolidates what used to be build_rtx40.sh/build_rtx50.sh (which sourced
# env_rtx*.sh then shelled out to gpu-cu/scripts/build_wheel_rtx*.sh, the
# old build_lib -> build_pkg -> package_wheel orchestrator). That
# orchestrator no longer exists -- tuned/build.sh + tuned/wheel.sh replace
# it directly.
set -euo pipefail

VARIANT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh" "$VARIANT"

cd "$FAISS_ROOT"

# Strip any Windows CRLF from tuned/ scripts (safe to run each time)
sed -i 's/\r//' tuned/*.sh tuned/wsl/*.sh 2>/dev/null || true

echo ""
echo "========================================="
echo " FAISS GPU CUDA $FAISS_CUDA_VER — ${GPU_TUNED_HW_LABEL} Build"
echo "========================================="
echo " Architecture  : $CUDA_ARCHS"
echo " Jobs          : $(nproc)"
echo " Log           : /tmp/faiss_build_${VARIANT}.log"
echo "========================================="
echo ""

{
    bash tuned/build.sh "$VARIANT"
    bash tuned/wheel.sh "$VARIANT"
} 2>&1 | tee "/tmp/faiss_build_${VARIANT}.log"

echo ""
echo "Build log saved to /tmp/faiss_build_${VARIANT}.log"

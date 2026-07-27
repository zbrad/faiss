#!/bin/bash
# tuned/wsl/verify.sh <variant> — verify the installed faiss-<variant>-<tag>
# wheel works (CPU + GPU). Usage (from PowerShell):
#   wsl -e bash tuned/wsl/verify.sh rtx50
# To install first, pass --install:
#   wsl -e bash tuned/wsl/verify.sh rtx50 --install
#
# Consolidates verify_rtx40.sh/verify_rtx50.sh.
set -euo pipefail

VARIANT="$1"
shift || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh" "$VARIANT"

# pip normalises hyphens to underscores in wheel filenames
WHEEL_PREFIX="faiss_${FAISS_VARIANT//-/_}"
WHEEL=$(ls "$FAISS_ROOT/build_output_${VARIANT}/${WHEEL_PREFIX}"-*.whl 2>/dev/null | head -1)

# Fallback: plain "faiss" wheel (no variant)
if [[ -z "$WHEEL" ]]; then
    WHEEL=$(ls "$FAISS_ROOT/build_output_${VARIANT}"/faiss-*.whl 2>/dev/null | head -1)
fi

if [[ "${1:-}" == "--install" ]]; then
    if [[ -z "$WHEEL" ]]; then
        echo "ERROR: No wheel found in $FAISS_ROOT/build_output_${VARIANT}/" >&2
        exit 1
    fi
    echo "Installing $WHEEL ..."
    pip3 install "$WHEEL" --break-system-packages --force-reinstall
fi

echo ""
echo "========================================="
echo " FAISS verify (${GPU_TUNED_HW_LABEL})"
echo "========================================="
python3 - <<'EOF'
import faiss

print(f"  faiss version : {faiss.__version__}")
print(f"  GPU count     : {faiss.get_num_gpus()}")

import numpy as np
d = 64
nb = 1000
xb = np.random.rand(nb, d).astype("float32")
index = faiss.IndexFlatL2(d)
index.add(xb)
D, I = index.search(xb[:5], 4)
assert I[0][0] == 0, "Self-search failed"
print(f"  CPU search    : OK ({nb} vectors, top-4)")

if faiss.get_num_gpus() > 0:
    res = faiss.StandardGpuResources()
    gpu_index = faiss.index_cpu_to_gpu(res, 0, index)
    D2, I2 = gpu_index.search(xb[:5], 4)
    assert I2[0][0] == 0, "GPU self-search failed"
    print(f"  GPU search    : OK (GPU 0)")

print("=========================================")
print("✓ All checks passed")
EOF

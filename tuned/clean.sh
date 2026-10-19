#!/bin/bash
# Clean build artifacts while preserving the wheel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAISS_ROOT="${FAISS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$FAISS_ROOT"

echo "Cleaning build artifacts..."

# Per-toolkit trees (tuned/build/<cuda>/, docs/ARCHITECTURE.md C2): remove the rebuildable parts only.
# Kept: dist/ (tarballs), wheel/, releases/ (test and smoke logs), ccache/, cuvs/ (the extracted cuVS release).
for d in "$FAISS_ROOT"/tuned/build/*/; do
    rm -rf "$d/cmake" "$d/stage" "$d/python" "$d/test_env"
done

# Leftovers from the old layout (no tuned script writes these any more)
rm -rf _build
rm -rf _build_rtx40
rm -rf _build_rtx50
rm -rf _build_gb10
rm -rf _build_python*
rm -rf _libfaiss_stage
rm -rf _libfaiss_stage_rtx40
rm -rf _libfaiss_stage_rtx50
rm -rf _libfaiss_stage_gb10
rm -rf build
rm -rf faiss/python/build
rm -rf faiss/python/dist
rm -rf .eggs
rm -rf *.egg-info

# Remove CMake cache
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "CMakeCache.txt" -delete
find . -name "cmake_install.cmake" -delete

echo "✓ Build artifacts cleaned"
echo "Note: tuned/build/<cuda>/ dist, wheel, releases, ccache and cuvs are preserved"

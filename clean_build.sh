#!/bin/bash
# Clean build artifacts while preserving the wheel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Cleaning build artifacts..."

# Remove build directories
rm -rf _build
rm -rf _build_python*
rm -rf _libfaiss_stage
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
echo "Note: build_output/ directory with wheels is preserved"

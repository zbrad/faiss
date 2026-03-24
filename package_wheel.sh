#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# Package FAISS wheel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON="${PYTHON:-python3}"
BUILD_OUTPUT_DIR="build_output"
PY_VER=$(${PYTHON} -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")
BUILD_DIR="_build_python_${PY_VER}"

echo "========================================="
echo "Packaging FAISS Wheel"
echo "========================================="
echo "Output directory: $BUILD_OUTPUT_DIR"
echo ""

# Verify build exists
if [ ! -d "$BUILD_DIR" ]; then
    echo "ERROR: Build directory not found. Run build_pkg_cuda132.sh first."
    exit 1
fi

# Create output directory
mkdir -p "$BUILD_OUTPUT_DIR"

# Build wheel
echo "[1/2] Building wheel with setuptools..."
cd "$BUILD_DIR"
$PYTHON setup.py bdist_wheel

# Copy wheel to output directory
echo "[2/2] Copying wheel to output..."
wheel_file=$(find dist -name "*.whl" -type f | head -1)
if [ -z "$wheel_file" ]; then
    echo "ERROR: No wheel file found"
    exit 1
fi

cp "$wheel_file" "../$BUILD_OUTPUT_DIR/"
wheel_basename=$(basename "$wheel_file")

echo ""
echo "========================================="
echo "✓ Wheel packaging complete"
echo "========================================="
echo "Wheel: $BUILD_OUTPUT_DIR/$wheel_basename"
echo ""
echo "To install, run:"
echo "  pip install $BUILD_OUTPUT_DIR/$wheel_basename"

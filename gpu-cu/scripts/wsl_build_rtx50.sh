#!/bin/bash
# Convenience entry-point — delegates to gpu-cu/wsl/build_rtx50.sh
# Usage:  wsl -e bash gpu-cu/scripts/wsl_build_rtx50.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../wsl/build_rtx50.sh" "$@"

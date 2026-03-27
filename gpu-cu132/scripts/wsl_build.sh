#!/bin/bash
# Convenience entry-point — delegates to gpu-cu132/wsl/build.sh
# Usage:  wsl -e bash gpu-cu132/scripts/wsl_build.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../wsl/build.sh" "$@"

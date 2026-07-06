#!/bin/bash
# Convenience entry-point — delegates to gpu-cu/wsl/verify_rtx40.sh --install
# Usage:  wsl -e bash gpu-cu/scripts/test_install_rtx40.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../wsl/verify_rtx40.sh" --install "$@"

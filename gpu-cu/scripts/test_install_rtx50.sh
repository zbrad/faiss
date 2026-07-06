#!/bin/bash
# Convenience entry-point — delegates to gpu-cu/wsl/verify_rtx50.sh --install
# Usage:  wsl -e bash gpu-cu/scripts/test_install_rtx50.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../wsl/verify_rtx50.sh" --install "$@"

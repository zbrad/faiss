#!/bin/bash
# Convenience entry-point — delegates to gpu-cu132/wsl/verify.sh --install
# Usage:  wsl -e bash gpu-cu132/scripts/test_install.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../wsl/verify.sh" --install "$@"

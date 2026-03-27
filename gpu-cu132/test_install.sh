#!/bin/bash
# Convenience entry-point — delegates to scripts/wsl/verify.sh --install
# Usage:  wsl -e bash test_install.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../scripts/wsl/verify.sh" --install "$@"

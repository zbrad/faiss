#!/bin/bash
# Convenience entry-point — delegates to scripts/wsl/build.sh
# Usage:  wsl -e bash wsl_build.sh
exec "$(dirname "${BASH_SOURCE[0]}")/../scripts/wsl/build.sh" "$@"

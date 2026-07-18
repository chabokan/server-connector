#!/bin/bash
# Backward-compatible wrapper (typo filename kept for older callers)
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/final.sh" "$@"

#!/usr/bin/env bash
# Wrapper de compatibilidad hacia create-debian-vm.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${DIR}/create-debian-vm.sh" "$@"

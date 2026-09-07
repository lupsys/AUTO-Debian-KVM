#!/usr/bin/env bash
# Redirección de compatibilidad para enlaces anteriores
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${DIR}/prepare-environment.sh" "$@"

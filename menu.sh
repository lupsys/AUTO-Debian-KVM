#!/usr/bin/env bash
set -euo pipefail

# URLs remotas de los scripts en tu GitHub
PREPARE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/refs/heads/main/prepare-enviroment.sh"
CREATE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/create-debian-vm.sh"

# Opciones del menú
options=(
  "Instalar dependencias (local)"
  "Instalar dependencias (GitHub)"
  "Instalar VM (local)"
  "Instalar VM (GitHub)"
  "Salir"
)

PS3="Seleccione una opción [1-${#options[@]}]: "
select opt in "${options[@]}"; do
  case "$opt" in
  "Instalar dependencias (local)")
    sudo bash prepare-environment.sh
    break
    ;;
  "Instalar dependencias (GitHub)")
    sudo bash -c "$(curl -fsSL "$PREPARE_URL")"
    break
    ;;
  "Instalar VM (local)")
    sudo bash create-debian-vm.sh
    break
    ;;
  "Instalar VM (GitHub)")
    sudo bash -c "$(curl -fsSL "$CREATE_URL")"
    break
    ;;
  "Salir")
    echo "Saliendo..."
    break
    ;;
  *)
    echo "Opción inválida."
    ;;
  esac
done

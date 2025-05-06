#!/usr/bin/env bash
set -euo pipefail

# URLs remotas
PREPARE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/refs/heads/main/prepare-enviroment.sh"
CREATE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/refs/heads/main/create-debian-vm2.sh"

PS3="Seleccione una opción: "
options=("Instalar dependencias (local)" "Instalar dependencias (GitHub)" "Instalar VM (local)" "Instalar VM (GitHub)" "Salir")
select opt in "${options[@]}"; do
  case $REPLY in
  1)
    echo "Ejecutando script de dependencias local"
    sudo bash prepare-environment.sh
    break
    ;;
  2)
    echo "Ejecutando script de dependencias desde GitHub"
    sudo bash -c "\$(curl -fsSL $PREPARE_URL)"
    break
    ;;
  3)
    echo "Ejecutando script de creación de VM local"
    sudo bash create-debian-vm.sh
    break
    ;;
  4)
    echo "Ejecutando script de creación de VM desde GitHub"
    sudo bash -c "\$(curl -fsSL $CREATE_URL)"
    break
    ;;
  5)
    echo "Saliendo."
    break
    ;;
  *)
    echo "Opción inválida."
    ;;
  esac
done

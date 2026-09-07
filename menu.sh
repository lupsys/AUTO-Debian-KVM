#!/usr/bin/env bash
set -euo pipefail

# URLs remotas de los scripts en GitHub
PREPARE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/prepare-enviroment.sh"
CREATE_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/create-debian-vm.sh"

# Función para detectar e instalar dependencias según la distro
detect_pkg_manager() {
  echo "--> Detectando e instalando dependencias..."
  if command -v paru &>/dev/null; then
    paru -S --noconfirm qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat libvirt iptables-nft
  elif command -v yay &>/dev/null; then
    yay -S --noconfirm qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat libvirt iptables-nft
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat libvirt iptables-nft
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y qemu-kvm libvirt virt-manager bridge-utils
  else
    echo "Gestor de paquetes no soportado." >&2
    exit 1
  fi
}

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
    detect_pkg_manager
    break
    ;;
  "Instalar dependencias (GitHub)")
    echo "--> Descargando prepare-environment.sh..."
    curl -fL --retry 3 --retry-delay 2 "${PREPARE_URL}?nocache=$(date +%s)" | sudo bash -x
    break
    ;;
  "Instalar VM (local)")
    if [ -f "create-debian-vm.sh" ]; then
      sudo bash create-debian-vm.sh
    else
      echo "Error: create-debian-vm.sh no existe localmente."
    fi
    break
    ;;
  "Instalar VM (GitHub)")
    echo "--> Descargando create-debian-vm.sh..."
    curl -fL --retry 3 --retry-delay 2 "${CREATE_URL}?nocache=$(date +%s)" | sudo bash -x
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

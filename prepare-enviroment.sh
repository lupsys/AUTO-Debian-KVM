#!/usr/bin/env bash
set -euo pipefail

# Este script comprueba e instala las dependencias necesarias:

# 1. Detectar si se ejecuta con sudo
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script con sudo."
  exit 1
fi

# 2. Paquetes requeridos
REQUIRED=(qemu-kvm libvirt-clients libvirt-daemon-system virt-install python3 openssl lsof fuser)

echo "🔍 Comprobando dependencias..."
for pkg in "${REQUIRED[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "  ❌ $pkg no instalado. Instalando..."
    apt-get update && apt-get install -y "$pkg"
  else
    echo "  ✅ $pkg ya está instalado"
  fi
done

# 3. Activar y arrancar servicios libvirt
echo "🔧 Habilitando y arrancando libvirtd"
systemctl enable --now libvirtd

# 4. Crear grupo kvm y añadir al usuario invocante
USER_REAL="${SUDO_USER:-$SUDO_USER}" # si se invoca con sudo, usa SUDO_USER
echo "🔧 Añadiendo \$USER_REAL al grupo kvm"
adduser "$USER_REAL" kvm || true

# 5. Mensaje final
echo "✅ Entorno preparado. Ejecuta ./create-debian-vm.sh desde tu carpeta de repo para crear la VM."

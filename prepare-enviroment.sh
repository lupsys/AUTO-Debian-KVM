#!/usr/bin/env bash
# prepare-environment.sh
# Script para preparar entorno KVM/QEMU: instalar dependencias y configurar grupos.
# Debe ejecutarse con sudo: sudo ./prepare-environment.sh
set -euo pipefail

# 1. Comprobar ejecución con sudo
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Ejecuta este script con sudo:"
  echo "  sudo $0"
  exit 1
fi

# 2. Determinar usuario invocante (SUDO_USER)
# Asumimos que si llegó aquí, el usuario está en sudoers de forma válida
TARGET_USER="${SUDO_USER:-$(id -un)}"
echo "🔧 Usuario objetivo: $TARGET_USER"

# 3. Paquetes requeridos
# virt-install -> virtinst, fuser -> psmisc
REQUIRED=(qemu-kvm libvirt-clients libvirt-daemon-system virtinst virt-manager python3 openssl lsof psmisc)

echo "🔍 Comprobando dependencias..."
for pkg in "${REQUIRED[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "  ❌ $pkg no instalado. Instalando..."
    apt-get update
    apt-get install -y "$pkg"
  else
    echo "  ✅ $pkg ya está instalado"
  fi
done

# 4. Habilitar libvirtd
echo "🔧 Habilitando y arrancando libvirtd..."
systemctl enable --now libvirtd

# 5. Añadir usuario al grupo kvm
echo "🔧 Añadiendo $TARGET_USER al grupo kvm..."
usermod -aG kvm "$TARGET_USER"
usermod -aG libvirt "$TARGET_USER"

# 6. Mensaje final
echo
cat <<EOF
✅ Entorno preparado para '$TARGET_USER'.

Dependencias instaladas: ${REQUIRED[*]}.
Usuario agregado al grupo kvm.

Ejecuta create-debian-vm.sh desde tu repositorio para crear la VM.
EOF

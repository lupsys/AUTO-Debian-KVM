#!/usr/bin/env bash
# Script para preparar entorno KVM/QEMU: instalar dependencias y configurar grupos.
# Debe ejecutarse con sudo: sudo ./prepare-environment.sh
set -euo pipefail

# 1. Comprobar ejecución con sudo
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Ejecuta este script con sudo:"
  echo "  sudo $0"
  exit 1
fi

# 2. Determinar usuario invocante
# SUDO_USER se define cuando se usa sudo
if [ -z "${SUDO_USER-}" ]; then
  echo "ERROR: Este script debe invocarse con sudo por un usuario sin privilegios root."
  exit 1
fi
TARGET_USER="$SUDO_USER"
echo "🔧 Usuario objetivo: $TARGET_USER"

# 3. Verificar que el usuario está en el grupo sudo
if ! getent group sudo | grep -qw "$TARGET_USER"; then
  cat <<EOF
ERROR: El usuario '$TARGET_USER' no pertenece al grupo sudo.
Para proceder, añade el usuario al sudoers ejecutando como root (su -) o pide a un administrador:
  usermod -aG sudo $TARGET_USER
EOF
  exit 1
fi

# 4. Paquetes requeridos
# En Debian, 'virt-install' se provee en 'virtinst'; 'fuser' en 'psmisc'
REQUIRED=(qemu-kvm libvirt-clients libvirt-daemon-system virtinst python3 openssl lsof psmisc)

echo "🔍 Comprobando dependencias..."
for pkg in "${REQUIRED[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "  ❌ $pkg no instalado. Instalando..."
    apt-get update && apt-get install -y "$pkg"
  else
    echo "  ✅ $pkg ya está instalado"
  fi
done

# 5. Activar y arrancar libvirtd
echo "🔧 Habilitando y arrancando libvirtd"
systemctl enable --now libvirtd

# 6. Añadir usuario al grupo kvm
echo "🔧 Añadiendo $TARGET_USER al grupo kvm"
usermod -aG kvm "$TARGET_USER"

# 7. Mensaje final
echo
cat <<EOF
✅ Entorno preparado para '$TARGET_USER'.

- Dependencias instaladas: ${REQUIRED[*]}.
- '$TARGET_USER' añadido al grupo kvm.

Puedes ejecutar create-debian-vm.sh desde tu repositorio para crear la VM.
EOF

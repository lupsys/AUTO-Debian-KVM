#!/usr/bin/env bash
set -euo pipefail

# Este script comprueba e instala las dependencias necesarias:

# 1. Detectar si se ejecuta con sudo
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script con sudo."
  exit 1
fi

# 2. Paquetes requeridos
# En Debian, 'virt-install' viene en 'virtinst' y 'fuser' en 'psmisc'
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

# 3. Activar y arrancar servicios libvirt
echo "🔧 Habilitando y arrancando libvirtd"
systemctl enable --now libvirtd

# 4. Determinar usuario invocante
if [ -n "${SUDO_USER-}" ]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(logname 2>/dev/null || echo "${USER:-root}")"
fi

echo "🔧 Usuario invocante detectado: $TARGET_USER"

# 5. Añadir usuario al grupo kvm
echo "🔧 Añadiendo $TARGET_USER al grupo kvm"
usermod -aG kvm "$TARGET_USER" || true

# 6. Configurar sudo para el usuario si no tiene privilegios
SUDOERS_FILE="/etc/sudoers.d/$TARGET_USER"
if [ ! -f "$SUDOERS_FILE" ]; then
  echo "🔧 Creando sudoers en $SUDOERS_FILE"
  echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" >"$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
else
  echo "🔧 Sudoers para $TARGET_USER ya existe"
fi

# 7. Mensaje final
cat <<EOF
✅ Entorno preparado.
- Usuario '$TARGET_USER' pertenece al grupo kvm.
- Sudo configurado en $SUDOERS_FILE.
- Dependencias instaladas: ${REQUIRED[*]}.
Ejecuta ./create-debian-vm.sh desde tu carpeta de repo para crear la VM.
EOF

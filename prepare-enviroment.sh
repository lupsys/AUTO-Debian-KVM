# prepare-environment.sh
#!/usr/bin/env bash
# Script para preparar entorno KVM/QEMU con dependencias y permisos.
# Se reejecuta automáticamente con privilegios (sudo o su).

# 0. Auto-escalado de privilegios
if [ "$EUID" -ne 0 ]; then
  # Intentar sudo sin contraseña
  if sudo -n true 2>/dev/null; then
    echo "🔄 Elevando privilegios con sudo..."
    exec sudo bash "$0" "$@"
  else
    echo "🔄 Elevando privilegios con 'su'..."
    exec su - root -c "bash '$0' $*"
  fi
fi

set -euo pipefail

# 1. Determinar usuario objetivo
# Si se invoca con sudo, SUDO_USER es el usuario original
# Si se ejecuta tras 'su', se puede pasar como primer argumento
if [ -n "${SUDO_USER-}" ]; then
  TARGET_USER="$SUDO_USER"
elif [ $# -ge 1 ]; then
  TARGET_USER="$1"
else
  echo "Uso: $0 [usuario]
Se detecta como root, especifica el usuario a configurar si es necesario."
  exit 1
fi

echo "🔧 Usuario objetivo: $TARGET_USER"

# 2. Paquetes requeridos
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

# 3. Activar y arrancar libvirtd
echo "🔧 Habilitando y arrancando libvirtd"
systemctl enable --now libvirtd

# 4. Añadir usuario al grupo kvm
echo "🔧 Añadiendo $TARGET_USER al grupo kvm"
usermod -aG kvm "$TARGET_USER" || true

# 5. Configurar sudoers sin contraseña
SUDOERS_FILE="/etc/sudoers.d/$TARGET_USER"
echo "🔧 Escribiendo configuración sudoers en $SUDOERS_FILE"
echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" >"$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

# 6. Mensaje final
cat <<EOF
✅ Entorno preparado para '$TARGET_USER'.
Dependencias: ${REQUIRED[*]}.
- '$TARGET_USER' en grupo kvm.
- Sudo sin contraseña en $SUDOERS_FILE.
Para crear la VM, ejecuta create-debian-vm.sh desde tu repo.
EOF

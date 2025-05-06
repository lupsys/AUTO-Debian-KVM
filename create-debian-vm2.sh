#!/usr/bin/env bash
# Crear VM Debian con preseed remoto y SPICE/QXL
# Ejecución: sudo ./create-debian-vm.sh
set -euo pipefail

# Preseed remoto (raw GitHub)
PRESEED_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/preseed/preseed.cfg"

# Credenciales aleatorias
USER_NAME="user$(tr -dc 'a-z0-9' </dev/urandom | head -c8 || true)"
PASSWORD="$(tr -dc 'a-z' </dev/urandom | head -c12 || true)"
PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD")

echo "🔐 Usuario: $USER_NAME  Contraseña: $PASSWORD"
# Guardar en home del usuario que ejecuta
CRED_FILE="${HOME}/user.txt"
echo -e "Usuario: $USER_NAME
Contraseña: $PASSWORD" >"$CRED_FILE"
echo "→ Credenciales en $CRED_FILE"

# Parámetros VM
VM_NAME="debian-$(date +%s)"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
ISO_URL="http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/"

# Lanzar instalación
echo "▶️ Iniciando instalación de $VM_NAME..."
virt-install \
  --name "$VM_NAME" \
  --ram 2048 --vcpus 2 \
  --disk path="$DISK_PATH",size=20 \
  --network network=default \
  --graphics spice --video qxl \
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --location "$ISO_URL" \
  --extra-args "auto=true priority=critical \
preseed/url=$PRESEED_URL \
passwd/username=$USER_NAME \
passwd/user-password-crypted=$PASSWORD_HASH \
locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=es interface=auto"

echo "✅ Instalación iniciada. Conecta con SPICE."

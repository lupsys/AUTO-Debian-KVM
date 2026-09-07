#!/usr/bin/env bash
# Crear VM Debian con preseed remoto y SPICE/QXL
# Ejecución: sudo ./create-debian-vm2.sh
set -euo pipefail

# Preseed remoto (raw GitHub)
PRESEED_URL="https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/preseed/preseed.cfg"

# Credenciales aleatorias
USER_NAME="debian"
PASSWORD="lupsys1234"
echo "🔐 Generando credenciales de usuario..."
echo "Usuario: ${USER_NAME}"
echo "Contraseña: ${PASSWORD}"
CRED_FILE="${HOME}/user.txt"
echo -e "Usuario: $USER_NAME\nContraseña: $PASSWORD" >"$CRED_FILE"

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
  --network network=default,model=virtio \
  --graphics spice --video virtio \
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --location "$ISO_URL" \
  --extra-args "auto=true priority=critical \
preseed/url=$PRESEED_URL \
locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=es \
netcfg/choose_interface=auto netcfg/dhcp_timeout=60"

echo "✅ Instalación iniciada. Conecta con SPICE."
echo "Recuerda tu usuario y Contraseña es:"
cat "$CRED_FILE"

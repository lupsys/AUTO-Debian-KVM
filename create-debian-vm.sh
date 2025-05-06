#!/usr/bin/env bash
set -euo pipefail

# --- Configuración ---
PORT=8000
PRESEED_FILE="preseed.cfg"
# IP del host en la red default de libvirt
HOST_IP="192.168.122.1"

PRESEED_DIR="/home/lupsys/preseed"
PRESEED_URL_BASE="http://${HOST_IP}:${PORT}"
VM_NAME="debian-auto-$(date +%s)"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
ISO_PATH="/home/lupsys/Downloads/debian-12.10.0-amd64-netinst.iso"

# Usuario objetivo: si hay SUDO_USER, úsalo; si no, el efectivo $USER
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${TARGET_USER}")

# Directorio de preseed en su home
PRESEED_DIR="${USER_HOME}/preseed"
mkdir -p "${PRESEED_DIR}"

# Cambia al directorio donde está preseed.cfg
cd "${PRESEED_DIR}"

cleanup() {
  echo "⏹ Parando servidor HTTP (PID ${SERVER_PID})…"
  kill "${SERVER_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "🚀 Arrancando servidor HTTP en ${HOST_IP}:${PORT} (dir: ${PRESEED_DIR})…"
# --bind a HOST_IP para que la VM pueda alcanzarlo
python3 -m http.server "${PORT}" --bind "${HOST_IP}" &
SERVER_PID=$!
sleep 1 # dale un momento para que el servidor esté listo

echo "💻 Lanzando virt-install para ${VM_NAME}…"
sudo virt-install \
  --name "${VM_NAME}" \
  --ram 2048 \
  --vcpus 2 \
  --disk path="${DISK_PATH}",size=20 \
  --os-variant debian12 \
  --network network=default \
  --graphics spice \
  --video qxl \
  --channel spicevmc,target_type=virtio \
  --location "${ISO_PATH}" \
  --extra-args "auto=true priority=critical \
preseed/url=${PRESEED_URL_BASE}/${PRESEED_FILE} \
ip=dhcp \
locale=en_US.UTF-8 \
keyboard-configuration/xkb-keymap=es \
console-setup/layoutcode=es \
hostname=${VM_NAME} \
interface=auto"

# Al salir (normal o Ctrl+C), el trap hará cleanup() y parará el HTTP
echo "✅ Instalación iniciada. Cuando termine, el servidor HTTP se detendrá automáticamente."

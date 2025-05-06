#!/usr/bin/env bash
set -euo pipefail

# --- 1. Determinar el home real del usuario que ejecuta el script ---
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~${TARGET_USER}")

# --- 2. Variables de configuración ---
PORT=8000
PRESEED_DIR="${USER_HOME}/AUTO-Debian-KVM"
PRESEED_URL_BASE="http://192.168.122.1:${PORT}"
VM_NAME="debian-auto-$(date +%s)"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
HOST_IP="192.168.122.1"
NETBOOT_URL="http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/"

mkdir -p "${PRESEED_DIR}"

# --- 3. Generar credenciales ---
USERNAME="user$(tr -dc 'a-z0-9' </dev/urandom | head -c3 || true)"
PASSWORD="$(tr -dc 'A-Za-z' </dev/urandom | head -c8 || true)"
PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD")

# --- 4. Volcar credenciales en host ---
cat >"${PRESEED_DIR}/user.txt" <<EOF
Usuario: ${USERNAME}
Contraseña: ${PASSWORD}
EOF
chmod 600 "${PRESEED_DIR}/user.txt"
echo "→ Credenciales guardadas en ${PRESEED_DIR}/user.txt"

# --- 5. Preparar preseed dinámico (opcional) ---
# Si quieres usar una plantilla con variables, copia aquí y reemplaza marcadores.
# Si no, asume que tu preseed.cfg ya incluye passwd/username y passwd/user-password-crypted.

# --- 6. Servidor HTTP para preseed ---
cd "${PRESEED_DIR}"
cleanup() {
  echo "⏹ Parando servidor HTTP (PID ${SERVER_PID})…"
  kill "${SERVER_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "🚀 Arrancando servidor HTTP en ${PRESEED_URL_BASE} (dir: ${PRESEED_DIR})…"
python3 -m http.server "${PORT}" --bind "${HOST_IP}" &
SERVER_PID=$!
sleep 1

# --- 7. Arrancar la VM con virt-install ---
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
  --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
  --location "${NETBOOT_URL}" \
  --extra-args "auto=true priority=critical \
preseed/url=${PRESEED_URL_BASE}/preseed.cfg \
ip=dhcp \
locale=en_US.UTF-8 \
keyboard-configuration/xkb-keymap=es \
console-setup/layoutcode=es \
hostname=${VM_NAME} \
interface=auto \
passwd/user-fullname=UsuarioAutomático \
passwd/username=${USERNAME} \
passwd/user-password-crypted=${PASSWORD_HASH}"

echo "✅ Instalación iniciada. Cuando termine, el servidor HTTP se detendrá automáticamente."

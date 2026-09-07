#!/usr/bin/env bash
# ==============================================================================
# prepare-environment.sh - AUTO-Debian-KVM
# Prepara el entorno KVM/QEMU: detecta la distro, instala paquetes necesarios,
# configura permisos de usuario y verifica el demonio libvirt y la red virtual.
# Compatible con: Arch Linux, Debian/Ubuntu, Fedora/RHEL, openSUSE.
# ==============================================================================
set -euo pipefail

# Colores para salida estética
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_CYAN='\033[1;36m'
C_BOLD='\033[1m'

info()    { echo -e "${C_CYAN}ℹ${C_RESET} $*"; }
success() { echo -e "${C_GREEN}✔${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
error()   { echo -e "${C_RED}✖ ERROR:${C_RESET} $*" >&2; }

CHECK_ONLY=false
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=true
fi

# 1. Verificar permisos de root si no es sólo comprobación
if [[ "$CHECK_ONLY" == false && "$EUID" -ne 0 ]]; then
  error "Este script requiere privilegios de superusuario para instalar paquetes."
  echo -e "Ejecútalo con: ${C_BOLD}sudo $0${C_RESET}"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$(id -un)}"

echo -e "${C_BOLD}====================================================${C_RESET}"
echo -e "${C_BOLD}   AUTO-Debian-KVM :: Preparación del Entorno       ${C_RESET}"
echo -e "${C_BOLD}====================================================${C_RESET}"
info "Usuario objetivo: ${C_BOLD}${TARGET_USER}${C_RESET}"

# 2. Verificar soporte de virtualización por hardware en el procesador
info "Comprobando aceleración de virtualización por hardware (VT-x / AMD-V)..."
VIRT_COUNT=$(grep -E -c '(vmx|svm)' /proc/cpuinfo || true)
if [[ "$VIRT_COUNT" -gt 0 ]]; then
  success "Soporte de virtualización por hardware detectado (${VIRT_COUNT} núcleos)."
else
  warn "No se encontraron extensiones VMX/SVM en /proc/cpuinfo. KVM puede ejecutarse lento (emulación pura)."
fi

# Si se ejecutó con --check-only terminamos aquí las comprobaciones básicas
if [[ "$CHECK_ONLY" == true ]]; then
  success "Comprobación básica completada."
  exit 0
fi

# 3. Detectar distribución y gestor de paquetes
detect_and_install() {
  info "Detectando gestor de paquetes del sistema..."
  
  if command -v pacman &>/dev/null; then
    info "Distribución basada en Arch Linux detectada (pacman)."
    pacman -Sy --noconfirm --needed \
      qemu-desktop \
      libvirt \
      virt-install \
      virt-manager \
      virt-viewer \
      dnsmasq \
      iptables-nft \
      bridge-utils \
      openbsd-netcat \
      edk2-ovmf \
      which \
      curl
  elif command -v apt-get &>/dev/null; then
    info "Distribución basada en Debian/Ubuntu detectada (apt)."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
      qemu-kvm \
      libvirt-daemon-system \
      libvirt-clients \
      virtinst \
      virt-manager \
      virt-viewer \
      bridge-utils \
      dnsmasq-base \
      ovmf \
      curl \
      netcat-openbsd
  elif command -v dnf &>/dev/null; then
    info "Distribución basada en Fedora/RHEL detectada (dnf)."
    dnf install -y \
      qemu-kvm \
      libvirt \
      libvirt-daemon-kvm \
      virt-install \
      virt-manager \
      virt-viewer \
      bridge-utils \
      edk2-ovmf \
      curl
  elif command -v zypper &>/dev/null; then
    info "Distribución openSUSE detectada (zypper)."
    zypper --non-interactive install -y \
      qemu-kvm \
      libvirt \
      libvirt-client \
      virt-install \
      virt-manager \
      virt-viewer \
      bridge-utils
  else
    error "No se pudo identificar un gestor de paquetes compatible (pacman, apt, dnf, zypper)."
    exit 1
  fi
}

detect_and_install

# 4. Habilitar y arrancar servicios de Libvirt
info "Configurando servicios de libvirt..."
if systemctl list-unit-files | grep -q "^libvirtd.service"; then
  systemctl enable --now libvirtd || true
fi

# Soporte para demonios modulares de libvirt (en distros modernas como Arch y Fedora)
for daemon in virtqemud virtnetworkd virtstoraged; do
  if systemctl list-unit-files | grep -q "^${daemon}.service"; then
    systemctl enable --now "${daemon}.service" || true
    systemctl enable --now "${daemon}-ro.socket" || true
    systemctl enable --now "${daemon}-admin.socket" || true
  fi
done

# 5. Agregar usuario a los grupos necesarios
info "Configurando grupos de usuario para '${TARGET_USER}'..."
for grp in kvm libvirt; do
  if getent group "$grp" &>/dev/null; then
    usermod -aG "$grp" "$TARGET_USER"
    success "Usuario '${TARGET_USER}' añadido al grupo '${grp}'."
  fi
done

# 6. Configurar y arrancar la red virtual 'default' de libvirt si no está activa
info "Verificando red virtual 'default' de libvirt..."
export LIBVIRT_DEFAULT_URI="qemu:///system"

if virsh net-info default &>/dev/null; then
  # Existe la red default
  if ! virsh net-list | grep -q "\<default\>"; then
    info "Iniciando red virtual 'default'..."
    virsh net-start default || true
  fi
  virsh net-autostart default || true
  success "Red virtual 'default' de libvirt activa y configurada en autostart."
else
  # Si no existe la red default, crearla desde la plantilla de libvirt
  DEFAULT_XML="/etc/libvirt/qemu/networks/default.xml"
  if [[ -f "$DEFAULT_XML" ]]; then
    virsh net-define "$DEFAULT_XML" || true
    virsh net-start default || true
    virsh net-autostart default || true
    success "Red virtual 'default' definida y activada desde $DEFAULT_XML."
  else
    warn "No se encontró $DEFAULT_XML. Se creará una definición de red NAT estándar..."
    TMP_NET_XML=$(mktemp)
    cat <<'NETXML' > "$TMP_NET_XML"
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
NETXML
    virsh net-define "$TMP_NET_XML" || true
    virsh net-start default || true
    virsh net-autostart default || true
    rm -f "$TMP_NET_XML"
    success "Red virtual 'default' creada y activada con éxito."
  fi
fi

# 7. Comprobar y configurar reglas de firewall (nftables / iptables)
info "Comprobando cortafuegos del host (nftables/iptables) para puentes virbr*..."
if [[ -f /etc/nftables.conf ]] && grep -q "chain input" /etc/nftables.conf && ! grep -q "virbr" /etc/nftables.conf; then
  warn "Se detectó que /etc/nftables.conf tiene una política restrictiva que bloquea virbr*."
  info "Añadiendo reglas de permiso para los puentes virbr* de KVM..."
  cp /etc/nftables.conf "/etc/nftables.conf.bak.$(date +%s)"
  sed -i '/chain input {/a \    iifname "virbr*" accept comment "allow Libvirt VM DHCP, DNS and traffic"' /etc/nftables.conf
  sed -i '/chain forward {/a \    iifname "virbr*" accept comment "allow traffic from Libvirt"\n    oifname "virbr*" ct state { established, related } accept comment "allow replies to Libvirt"' /etc/nftables.conf
  if command -v nft &>/dev/null; then
    nft -f /etc/nftables.conf || true
    success "Reglas de nftables actualizadas y aplicadas en el kernel."
  fi
else
  success "Cortafuegos verificado (puentes virbr* permitidos)."
fi

# 7. Resumen final
echo
echo -e "${C_GREEN}${C_BOLD}✔ ¡Entorno KVM/QEMU configurado con éxito!${C_RESET}"
echo -e "• Dependencias instaladas y actualizadas."
echo -e "• Servicios de virtualización activos."
echo -e "• Red NAT de libvirt ('default') operativa."
echo -e "• Usuario '${C_BOLD}${TARGET_USER}${C_RESET}' agregado a los grupos ${C_BOLD}kvm${C_RESET} y ${C_BOLD}libvirt${C_RESET}."
echo
echo -e "${C_YELLOW}Nota:${C_RESET} Si es la primera vez que se añade tu usuario a los grupos, puede ser necesario cerrar y reabrir sesión (o ejecutar 'newgrp libvirt') para aplicar los permisos sin sudo."

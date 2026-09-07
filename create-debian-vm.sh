#!/usr/bin/env bash
# ==============================================================================
# create-debian-vm.sh - AUTO-Debian-KVM
# Despliegue automatizado y desatendido de máquinas virtuales Debian en KVM/QEMU.
# Soporta inyección nativa de preseed en initrd, perfiles (Server, Docker, Desktop),
# configuración de recursos, inyección de claves SSH y modo interactivo/CLI.
# ==============================================================================
set -euo pipefail

# Colores para salida estética en terminal
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_CYAN='\033[1;36m'
C_BOLD='\033[1m'

info()    { echo -e "${C_CYAN}ℹ${C_RESET} $*"; }
success() { echo -e "${C_GREEN}✔${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
error()   { echo -e "${C_RED}✖ ERROR:${C_RESET} $*" >&2; }

# Directorio base del proyecto
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Valores por defecto
DEFAULT_NAME="debian-$(date +%m%d-%H%M)"
VM_NAME=""
RAM_MB=""
VCPUS=""
DISK_GB=""
PROFILE=""
USER_NAME="debian"
USER_PASS=""
ROOT_PASS=""
SSH_KEY_FILE=""
NOPASSWD_SUDO=false
DRY_RUN=false
NON_INTERACTIVE=false
ISO_PATH=""
OS_VARIANT="debian12"
POOL_DIR="/var/lib/libvirt/images"

# Red default y conexión por defecto a QEMU System
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Ayuda y uso CLI
show_help() {
  cat <<EOF
Uso: $0 [OPCIONES]

Opciones:
  -n, --name NOMBRE           Nombre de la máquina virtual (Defecto: debian-<timestamp>)
  -m, --ram MB                Memoria RAM en MB (Defecto: 2048 server/docker, 4096 desktop)
  -c, --cpus NUM              Número de vCPUs (Defecto: 2)
  -d, --disk GB               Tamaño del disco en GB (Defecto: 20)
  -p, --profile PERFIL        Perfil de VM: minimal | docker | desktop-xfce | desktop-gnome
  -u, --user USUARIO          Nombre del usuario principal (Defecto: debian)
      --password PASS         Contraseña del usuario (Defecto: se genera una aleatoria segura)
      --root-password PASS    Contraseña de root (Defecto: igual a la del usuario)
  -k, --ssh-key ARCHIVO       Ruta a tu clave pública SSH (ej. ~/.ssh/id_rsa.pub)
      --nopasswd-sudo         Habilitar sudo sin contraseña para el usuario
      --iso ARCHIVO           Ruta a una imagen ISO local o URL alternativa
      --os-variant VARIANTE   Variante de SO para virt-install (Defecto: debian12)
      --dry-run               Muestra el comando virt-install y el preseed sin ejecutarlo
  -y, --non-interactive       No solicitar confirmación interactiva
  -h, --help                  Muestra este mensaje de ayuda

Ejemplos:
  $0
  $0 --name srv-docker --profile docker --ram 4096 --disk 30 --ssh-key ~/.ssh/id_rsa.pub
  $0 --name pc-xfce --profile desktop-xfce --ram 4096 --cpus 4 --nopasswd-sudo
EOF
  exit 0
}

# Parsear argumentos CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) VM_NAME="$2"; shift 2 ;;
    -m|--ram) RAM_MB="$2"; shift 2 ;;
    -c|--cpus) VCPUS="$2"; shift 2 ;;
    -d|--disk) DISK_GB="$2"; shift 2 ;;
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -u|--user) USER_NAME="$2"; shift 2 ;;
    --password) USER_PASS="$2"; shift 2 ;;
    --root-password) ROOT_PASS="$2"; shift 2 ;;
    -k|--ssh-key) SSH_KEY_FILE="$2"; shift 2 ;;
    --nopasswd-sudo) NOPASSWD_SUDO=true; shift ;;
    --iso) ISO_PATH="$2"; shift 2 ;;
    --os-variant) OS_VARIANT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    -h|--help) show_help ;;
    *) error "Opción desconocida: $1"; show_help ;;
  esac
done

# Función para generar contraseñas aleatorias legibles y seguras
generate_password() {
  local pass
  pass=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 12 || true)
  if [[ -z "$pass" || ${#pass} -lt 8 ]]; then
    pass="Debian$(date +%s)"
  fi
  echo "$pass"
}

# Si no se pasó por CLI, asignar o solicitar valores
[[ -z "$VM_NAME" ]] && VM_NAME="$DEFAULT_NAME"
[[ -z "$PROFILE" ]] && PROFILE="minimal"

# Ajustar recursos por defecto según el perfil si no se especificaron
case "$PROFILE" in
  desktop*|gnome*|xfce*)
    [[ -z "$RAM_MB" ]] && RAM_MB=4096
    [[ -z "$VCPUS" ]]  && VCPUS=2
    [[ -z "$DISK_GB" ]] && DISK_GB=25
    ;;
  docker*)
    [[ -z "$RAM_MB" ]] && RAM_MB=3072
    [[ -z "$VCPUS" ]]  && VCPUS=2
    [[ -z "$DISK_GB" ]] && DISK_GB=25
    ;;
  *)
    [[ -z "$RAM_MB" ]] && RAM_MB=2048
    [[ -z "$VCPUS" ]]  && VCPUS=2
    [[ -z "$DISK_GB" ]] && DISK_GB=10
    ;;
esac

# Validar tamaño mínimo de disco (mínimo 10 GB)
if [[ "$DISK_GB" -lt 10 ]]; then
  warn "El tamaño de disco mínimo para la instalación es 10 GB. Ajustando a 10 GB..."
  DISK_GB=10
fi

if [[ -z "$USER_PASS" ]]; then
  USER_PASS="debian1234"
fi
if [[ -z "$ROOT_PASS" ]]; then
  ROOT_PASS="$USER_PASS"
fi

# Validar clave SSH si se especificó
SSH_KEY_CONTENT=""
if [[ -n "$SSH_KEY_FILE" ]]; then
  # Expandir tilde si existe
  SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"
  if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_KEY_CONTENT="$(cat "$SSH_KEY_FILE")"
    info "Clave SSH cargada desde: $SSH_KEY_FILE"
  else
    warn "Archivo de clave SSH no encontrado: $SSH_KEY_FILE (se omitirá)."
  fi
fi

# Comprobar si virt-install está instalado
if ! command -v virt-install &>/dev/null; then
  error "virt-install no está instalado. Ejecuta primero: sudo ./prepare-environment.sh"
  exit 1
fi

# Comprobar si la red de libvirt está activa
if command -v virsh &>/dev/null; then
  if ! virsh -c qemu:///system net-list 2>/dev/null | grep -q "\<default\>"; then
    warn "La red virtual 'default' de libvirt no parece estar activa."
    info "Intentando iniciar la red virtual default..."
    sudo virsh -c qemu:///system net-start default 2>/dev/null || true
  fi
fi

# Ruta del disco virtual de la máquina
DISK_PATH="${POOL_DIR}/${VM_NAME}.qcow2"

echo -e "${C_BOLD}====================================================${C_RESET}"
echo -e "${C_BOLD}      AUTO-Debian-KVM :: Creación de VM             ${C_RESET}"
echo -e "${C_BOLD}====================================================${C_RESET}"
echo -e "• ${C_BOLD}Nombre VM:${C_RESET}     $VM_NAME"
echo -e "• ${C_BOLD}Perfil:${C_RESET}        $PROFILE"
echo -e "• ${C_BOLD}vCPUs:${C_RESET}         $VCPUS"
echo -e "• ${C_BOLD}Memoria RAM:${C_RESET}   ${RAM_MB} MB"
echo -e "• ${C_BOLD}Disco:${C_RESET}         ${DISK_GB} GB (${DISK_PATH})"
echo -e "• ${C_BOLD}Usuario:${C_RESET}       $USER_NAME"
echo -e "• ${C_BOLD}Contraseña:${C_RESET}    $USER_PASS"
if [[ -n "$SSH_KEY_CONTENT" ]]; then
  echo -e "• ${C_BOLD}Clave SSH:${C_RESET}     Inyectada automáticamente"
fi
if [[ "$NOPASSWD_SUDO" == true ]]; then
  echo -e "• ${C_BOLD}Sudo:${C_RESET}          Sin contraseña (NOPASSWD)"
fi
echo -e "${C_BOLD}====================================================${C_RESET}"

if [[ "$NON_INTERACTIVE" == false && "$DRY_RUN" == false ]]; then
  read -r -p "¿Deseas continuar con la creación de la VM? [S/n]: " CONFIRM
  CONFIRM=${CONFIRM:-S}
  if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
    warn "Operación cancelada por el usuario."
    exit 0
  fi
fi

# Crear archivo preseed dinámico temporal con nombre exacto preseed.cfg
TEMP_DIR="$(mktemp -d /tmp/auto-debian-XXXXXX)"
TEMP_PRESEED="${TEMP_DIR}/preseed.cfg"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Construcción de paquetes y configuración según el perfil
EXTRA_PACKAGES="sudo curl wget git openssh-server qemu-guest-agent ca-certificates neovim htop net-tools"
TASKSEL_TASKS="standard, ssh-server"
GRAPHICS_CONFIG=""

case "$PROFILE" in
  docker)
    EXTRA_PACKAGES="$EXTRA_PACKAGES docker.io docker-compose-plugin"
    ;;
  desktop-xfce)
    TASKSEL_TASKS="standard, ssh-server, xfce-desktop"
    EXTRA_PACKAGES="$EXTRA_PACKAGES spice-vdagent xserver-xorg-video-qxl lightdm"
    ;;
  desktop-gnome)
    TASKSEL_TASKS="standard, ssh-server, gnome-desktop"
    EXTRA_PACKAGES="$EXTRA_PACKAGES spice-vdagent"
    ;;
esac

# Generar contenido del preseed dinámico
cat <<EOF > "$TEMP_PRESEED"
### Localización e Idioma ###
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i console-setup/layoutcode string es
d-i keyboard-configuration/xkb-keymap select es
d-i time/zone string Europe/Madrid
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

### Red ###
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${VM_NAME}
d-i netcfg/get_domain string localdomain
d-i netcfg/wireless_wep string

### Mirror ###
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

### Cuentas ###
d-i passwd/root-login boolean true
d-i passwd/root-password password ${ROOT_PASS}
d-i passwd/root-password-again password ${ROOT_PASS}
d-i passwd/user-fullname string ${USER_NAME}
d-i passwd/username string ${USER_NAME}
d-i passwd/user-password password ${USER_PASS}
d-i passwd/user-password-again password ${USER_PASS}
d-i passwd/user-default-groups string audio cdrom video sudo docker

### Particionado ###
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### Paquetes ###
tasksel tasksel/first multiselect ${TASKSEL_TASKS}
d-i pkgsel/include string ${EXTRA_PACKAGES}
d-i pkgsel/upgrade select full-upgrade
popularity-contest popularity-contest/participate boolean false

### GRUB ###
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string /dev/vda
d-i grub-pc/install_devices string /dev/vda
d-i grub-pc/install_devices_disks_changed boolean true
d-i debian-installer/add-kernel-opts string console=tty0 console=ttyS0,115200n8

### Script Post-Instalación (Late Command) ###
EOF

# Preparar comando de post-instalación si hay claves SSH o sudo nopasswd
LATE_COMMANDS=()

if [[ "$NOPASSWD_SUDO" == true ]]; then
  LATE_COMMANDS+=("echo '${USER_NAME} ALL=(ALL:ALL) NOPASSWD: ALL' > /target/etc/sudoers.d/99-${USER_NAME}-nopasswd && chmod 0440 /target/etc/sudoers.d/99-${USER_NAME}-nopasswd")
fi

if [[ -n "$SSH_KEY_CONTENT" ]]; then
  LATE_COMMANDS+=("mkdir -p /target/home/${USER_NAME}/.ssh && chmod 700 /target/home/${USER_NAME}/.ssh && echo '${SSH_KEY_CONTENT}' >> /target/home/${USER_NAME}/.ssh/authorized_keys && chmod 600 /target/home/${USER_NAME}/.ssh/authorized_keys && chown -R 1000:1000 /target/home/${USER_NAME}/.ssh")
fi

# Habilitar servicios como qemu-guest-agent y docker si corresponde
LATE_COMMANDS+=("in-target systemctl enable qemu-guest-agent || true")
if [[ "$PROFILE" == "docker" ]]; then
  LATE_COMMANDS+=("in-target systemctl enable docker || true")
fi

if [[ ${#LATE_COMMANDS[@]} -gt 0 ]]; then
  # Unir comandos con ';'
  JOINED_COMMANDS=$(IFS="; "; echo "${LATE_COMMANDS[*]}")
  cat <<EOF >> "$TEMP_PRESEED"
d-i preseed/late_command string ${JOINED_COMMANDS}
EOF
fi

cat <<EOF >> "$TEMP_PRESEED"
### Finalización ###
d-i finish-install/reboot_in_progress note
EOF

# Determinar origen de instalación (mirror web o ISO local)
INSTALL_LOCATION="http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/"
if [[ -n "$ISO_PATH" ]]; then
  INSTALL_LOCATION="$ISO_PATH"
fi

# Configuración de gráficos y canales
VIRT_GRAPHICS=()
if [[ "$PROFILE" =~ ^desktop ]]; then
  VIRT_GRAPHICS=(
    --graphics spice,listen=127.0.0.1
    --video virtio
    --channel spicevmc,target_type=virtio,name=com.redhat.spice.0
    --channel unix,target_type=virtio,name=org.qemu.guest_agent.0
  )
else
  # Servidores sin entorno gráfico: SPICE básico + consola serie pty + guest agent
  VIRT_GRAPHICS=(
    --graphics spice,listen=127.0.0.1
    --video virtio
    --channel spicevmc,target_type=virtio,name=com.redhat.spice.0
    --channel unix,target_type=virtio,name=org.qemu.guest_agent.0
    --console pty,target_type=serial
  )
fi

# Preparar comando virt-install
INSTALL_CMD=(
  virt-install
  --connect qemu:///system
  --name "$VM_NAME"
  --ram "$RAM_MB"
  --vcpus "$VCPUS"
  --disk "path=${DISK_PATH},size=${DISK_GB},format=qcow2,bus=virtio"
  --os-variant "$OS_VARIANT"
  --network "network=default,model=virtio"
  "${VIRT_GRAPHICS[@]}"
  --location "$INSTALL_LOCATION"
  --initrd-inject "$TEMP_PRESEED"
  --extra-args "auto=true priority=critical file=/preseed.cfg preseed/file=/preseed.cfg locale=en_US.UTF-8 keyboard-configuration/xkb-keymap=es netcfg/choose_interface=auto netcfg/dhcp_timeout=60 hostname=${VM_NAME} domain=localdomain"
  --noautoconsole
)

if [[ "$DRY_RUN" == true ]]; then
  info "Modo Dry-Run activado. Comando virt-install:"
  echo "${INSTALL_CMD[*]}"
  echo
  info "Preseed generado:"
  cat "$TEMP_PRESEED"
  exit 0
fi

# Ejecutar virt-install (sin sudo si el usuario pertenece al grupo libvirt)
info "Lanzando instalación desatendida mediante virt-install..."
if groups | grep -E -q '\<(libvirt|kvm)\>'; then
  "${INSTALL_CMD[@]}"
elif [[ "$EUID" -eq 0 ]]; then
  "${INSTALL_CMD[@]}"
else
  sudo "${INSTALL_CMD[@]}"
fi

# Guardar credenciales en un archivo local
CREDS_FILE="${PROJECT_DIR}/creds-${VM_NAME}.txt"
cat <<EOF > "$CREDS_FILE"
==================================================
 Credenciales de la Máquina Virtual: ${VM_NAME}
==================================================
Fecha de creación: $(date)
Perfil:            ${PROFILE}
vCPUs:             ${VCPUS}
RAM:               ${RAM_MB} MB
Disco:             ${DISK_GB} GB (${DISK_PATH})

Usuario:           ${USER_NAME}
Contraseña:        ${USER_PASS}
Root Contraseña:   ${ROOT_PASS}
$(if [[ -n "$SSH_KEY_FILE" ]]; then echo "Clave SSH:         ${SSH_KEY_FILE}"; fi)
$(if [[ "$NOPASSWD_SUDO" == true ]]; then echo "Sudo:              NOPASSWD (sin contraseña)"; fi)
==================================================
EOF
chmod 600 "$CREDS_FILE" 2>/dev/null || true

echo
success "¡Máquina virtual '${C_BOLD}${VM_NAME}${C_RESET}' creada y arrancada para su instalación!"
echo -e "Las credenciales han sido guardadas en: ${C_BOLD}${CREDS_FILE}${C_RESET}"
echo
echo -e "${C_CYAN}${C_BOLD}Comandos útiles para conectar:${C_RESET}"
echo -e "• ${C_BOLD}Ver consola gráfica (SPICE):${C_RESET} virt-viewer -c qemu:///system ${VM_NAME} &"
echo -e "• ${C_BOLD}Ver consola serie (Texto):${C_RESET}   virsh -c qemu:///system console ${VM_NAME}"
echo -e "• ${C_BOLD}Consultar estado de la VM:${C_RESET}   virsh -c qemu:///system dominfo ${VM_NAME}"
echo -e "• ${C_BOLD}Obtener IP cuando termine:${C_RESET}   virsh -c qemu:///system domifaddr ${VM_NAME}"
echo

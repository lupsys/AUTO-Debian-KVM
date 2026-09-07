#!/usr/bin/env bash
# ==============================================================================
# menu.sh - AUTO-Debian-KVM
# Centro de control principal interactivo y asistente de despliegue.
# ==============================================================================
set -euo pipefail

# Colores y estilos ANSI
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null && pwd)"
REPO_URL="https://github.com/lupsys/AUTO-Debian-KVM.git"

# Si no estamos dentro del repositorio clonado, clonarlo o descargarlo
ensure_repo() {
  if [[ ! -f "${SCRIPT_DIR}/create-debian-vm.sh" ]]; then
    echo -e "${C_CYAN}ℹ Repositorio local no detectado. Clonando AUTO-Debian-KVM...${C_RESET}"
    local TARGET_DIR="${HOME}/AUTO-Debian-KVM"
    if [[ ! -d "$TARGET_DIR" ]]; then
      git clone "$REPO_URL" "$TARGET_DIR"
    fi
    cd "$TARGET_DIR"
    SCRIPT_DIR="$TARGET_DIR"
    chmod +x *.sh
  fi
}

# Banner visual
banner() {
  clear 2>/dev/null || true
  echo -e "${C_CYAN}${C_BOLD}"
  cat <<'EOF'
    _   _   _ _____ ___        ____       _     _             
   / \ | | | |_   _/ _ \      |  _ \  ___| |__ (_) __ _ _ __  
  / _ \| | | | | || | | |_____| | | |/ _ \ '_ \| |/ _` | '_ \ 
 / ___ \ |_| | | || |_| |_____| |_| |  __/ |_) | | (_| | | | |
/_/   \_\___/  |_| \___/      |____/ \___|_.__/|_|\__,_|_| |_|
                  KVM / QEMU Unattended Installer
EOF
  echo -e "${C_WHITE}    Soporte Universal: Arch | Debian/Ubuntu | Fedora | openSUSE${C_RESET}"
  echo -e "${C_BLUE}======================================================================${C_RESET}"
}

# Menú interactivo
main_menu() {
  ensure_repo

  while true; do
    banner
    echo -e "${C_BOLD}Selecciona una opción:${C_RESET}\n"
    echo -e "  ${C_GREEN}1)${C_RESET} ${C_BOLD}🚀 Despliegue Rápido 1-Clic${C_RESET} (Debian Server Minimal 2GB RAM / 10GB Disco)"
    echo -e "  ${C_CYAN}2)${C_RESET} ${C_BOLD}🛠️  Crear VM Personalizada${C_RESET} (Seleccionar Perfil, RAM, CPUs, Disco, SSH)"
    echo -e "  ${C_YELLOW}3)${C_RESET} ${C_BOLD}📦 Preparar Entorno KVM${C_RESET} (Instalar dependencias y verificar red libvirt)"
    echo -e "  ${C_MAGENTA}4)${C_RESET} ${C_BOLD}📊 Administrar VMs${C_RESET} (Listar, ver IPs, abrir SPICE/consola, apagar, borrar)"
    echo -e "  ${C_WHITE}5)${C_RESET} ${C_BOLD}🔄 Actualizar Repositorio${C_RESET} (git pull para obtener última versión)"
    echo -e "  ${C_RED}0)${C_RESET} ${C_BOLD}🚪 Salir${C_RESET}\n"
    echo -e "${C_BLUE}----------------------------------------------------------------------${C_RESET}"
    
    read -r -p "Ingresa tu opción [0-5]: " OPTION
    echo

    case "$OPTION" in
      1)
        echo -e "${C_GREEN}▶ Iniciando despliegue rápido (Minimal, 10GB Disco, 2GB RAM, debian/debian1234)...${C_RESET}"
        "${SCRIPT_DIR}/create-debian-vm.sh" \
          --profile minimal \
          --disk 10 \
          --ram 2048 \
          --cpus 2 \
          --user debian \
          --password debian1234 \
          -y
        read -r -p "Presiona Enter para volver al menú..." _
        ;;
      2)
        custom_vm_wizard
        ;;
      3)
        echo -e "${C_YELLOW}▶ Ejecutando preparación del entorno KVM...${C_RESET}"
        if [[ "$EUID" -eq 0 ]]; then
          "${SCRIPT_DIR}/prepare-environment.sh"
        else
          sudo "${SCRIPT_DIR}/prepare-environment.sh"
        fi
        read -r -p "Presiona Enter para volver al menú..." _
        ;;
      4)
        "${SCRIPT_DIR}/manage-vms.sh"
        ;;
      5)
        echo -e "${C_CYAN}▶ Actualizando repositorio local desde GitHub...${C_RESET}"
        cd "${SCRIPT_DIR}" && git pull origin main || true
        chmod +x *.sh || true
        read -r -p "Presiona Enter para continuar..." _
        ;;
      0|q|exit)
        echo -e "${C_GREEN}¡Hasta pronto!${C_RESET}"
        exit 0
        ;;
      *)
        echo -e "${C_RED}Opción inválida.${C_RESET}"
        sleep 1
        ;;
    esac
  done
}

# Asistente interactivo paso a paso para crear VM
custom_vm_wizard() {
  banner
  echo -e "${C_BOLD}--- Asistente de Creación de Máquina Virtual Debian ---${C_RESET}\n"
  
  # 1. Nombre
  local def_name="debian-$(date +%m%d-%H%M)"
  read -r -p "Nombre de la VM [${def_name}]: " VM_NAME
  VM_NAME="${VM_NAME:-$def_name}"

  # 2. Perfil
  echo -e "\n${C_BOLD}Selecciona el perfil de instalación:${C_RESET}"
  echo "1) minimal        - Servidor ligero sin entorno gráfico (SSH, QEMU Guest Agent)"
  echo "2) docker         - Servidor con Docker y Docker Compose preinstalados"
  echo "3) desktop-xfce   - Entorno de escritorio ligero XFCE + SPICE"
  echo "4) desktop-gnome  - Entorno de escritorio completo GNOME + SPICE"
  read -r -p "Opción [1-4, defecto 1]: " PROF_OPT
  case "${PROF_OPT:-1}" in
    2) PROFILE="docker" ;;
    3) PROFILE="desktop-xfce" ;;
    4) PROFILE="desktop-gnome" ;;
    *) PROFILE="minimal" ;;
  esac

  # 3. vCPUs
  local def_cpu=2
  read -r -p "Número de vCPUs [${def_cpu}]: " VCPUS
  VCPUS="${VCPUS:-$def_cpu}"

  # 4. Memoria RAM
  local def_ram=2048
  [[ "$PROFILE" =~ desktop ]] && def_ram=4096
  [[ "$PROFILE" == "docker" ]] && def_ram=3072
  read -r -p "Memoria RAM en MB [${def_ram}]: " RAM_MB
  RAM_MB="${RAM_MB:-$def_ram}"

  # 5. Disco
  local def_disk=10
  [[ "$PROFILE" =~ desktop|docker ]] && def_disk=20
  read -r -p "Tamaño de disco en GB (mínimo 10GB) [${def_disk}]: " DISK_GB
  DISK_GB="${DISK_GB:-$def_disk}"
  if [[ "$DISK_GB" -lt 10 ]]; then
    DISK_GB=10
  fi

  # 6. Usuario
  local def_user="debian"
  read -r -p "Nombre de usuario [${def_user}]: " USER_NAME
  USER_NAME="${USER_NAME:-$def_user}"

  # 7. Contraseña
  local def_pass="debian1234"
  read -r -p "Contraseña de usuario y root [${def_pass}]: " INPUT_PASS
  local USER_PASS="${INPUT_PASS:-$def_pass}"

  # 8. Clave SSH
  local def_ssh="${HOME}/.ssh/id_rsa.pub"
  [[ ! -f "$def_ssh" && -f "${HOME}/.ssh/id_ed25519.pub" ]] && def_ssh="${HOME}/.ssh/id_ed25519.pub"
  local SSH_FLAG=()
  if [[ -f "$def_ssh" ]]; then
    read -r -p "Inyectar clave SSH pública (${def_ssh})? [S/n]: " USE_SSH
    USE_SSH="${USE_SSH:-S}"
    if [[ "$USE_SSH" =~ ^[sSyY]$ ]]; then
      SSH_FLAG=(--ssh-key "$def_ssh")
    fi
  fi

  # 8. Sudo sin contraseña
  read -r -p "¿Configurar sudo sin contraseña para '${USER_NAME}'? [s/N]: " USE_NOPASSWD
  local NOPASSWD_FLAG=()
  if [[ "$USE_NOPASSWD" =~ ^[sSyY]$ ]]; then
    NOPASSWD_FLAG=(--nopasswd-sudo)
  fi

  echo
  "${SCRIPT_DIR}/create-debian-vm.sh" \
    --name "$VM_NAME" \
    --profile "$PROFILE" \
    --cpus "$VCPUS" \
    --ram "$RAM_MB" \
    --disk "$DISK_GB" \
    --user "$USER_NAME" \
    --password "$USER_PASS" \
    "${SSH_FLAG[@]}" \
    "${NOPASSWD_FLAG[@]}"

  read -r -p "Presiona Enter para volver al menú..." _
}

# Ejecutar el menú principal
main_menu

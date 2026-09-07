#!/usr/bin/env bash
# ==============================================================================
# manage-vms.sh - AUTO-Debian-KVM
# Administrador de ciclo de vida de máquinas virtuales KVM/libvirt.
# Permite seleccionar VMs por NÚMERO (ID), consultar IPs por múltiples fuentes
# (Guest-Agent, DHCP lease, ARP) y realizar acciones sin escribir nombres largos.
# ==============================================================================
set -euo pipefail

# Colores para terminal
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'

info()    { echo -e "${C_CYAN}ℹ${C_RESET} $*"; }
success() { echo -e "${C_GREEN}✔${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
error()   { echo -e "${C_RED}✖ ERROR:${C_RESET} $*" >&2; }

export LIBVIRT_DEFAULT_URI="qemu:///system"

# Comprobar disponibilidad de virsh
if ! command -v virsh &>/dev/null; then
  error "virsh no está disponible. Ejecuta: sudo ./prepare-environment.sh"
  exit 1
fi

# Obtener lista de nombres de VMs en un array global
get_vms_array() {
  VMS=()
  while IFS= read -r vm; do
    [[ -n "$vm" ]] && VMS+=("$vm")
  done < <(virsh list --all --name 2>/dev/null | grep -v '^$' || true)
}

# Detector robusto de IP utilizando múltiples fuentes
detect_ip() {
  local vm="$1"
  local ip=""

  # 1. Obtener MACs de la interfaz de la VM y buscar en asignaciones DHCP de libvirt (inmediato durante y tras la instalación)
  local macs
  macs=$(virsh domiflist "$vm" 2>/dev/null | awk '/[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/ {print tolower($5)}')
  if [[ -n "$macs" ]]; then
    local leases
    leases=$(virsh net-dhcp-leases default 2>/dev/null || true)
    for m in $macs; do
      ip=$(echo "$leases" | grep -i "$m" | awk '{print $5}' | cut -d/ -f1 | head -n 1 || true)
      if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
      fi
    done
  fi

  # 2. Intentar con virsh domifaddr --source lease
  ip=$(virsh domifaddr "$vm" --source lease 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi

  # 3. Intentar con QEMU Guest Agent (cuando el SO ya ha arrancado completamente)
  ip=$(virsh domifaddr "$vm" --source agent 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^127\.' | head -n 1 || true)
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi

  # 4. Intentar con virsh domifaddr --source arp
  ip=$(virsh domifaddr "$vm" --source arp 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi

  # 5. Buscar en la tabla ARP / vecinos del host (ip neigh)
  if [[ -n "$macs" ]]; then
    local neighs
    neighs=$(ip neigh show 2>/dev/null || true)
    for m in $macs; do
      ip=$(echo "$neighs" | grep -i "$m" | awk '{print $1}' | head -n 1 || true)
      if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
      fi
    done

    # 6. Buscar en el archivo de estado de dnsmasq si existe
    if [[ -f "/var/lib/libvirt/dnsmasq/virbr0.status" ]]; then
      for m in $macs; do
        ip=$(grep -B 3 -i "$m" /var/lib/libvirt/dnsmasq/virbr0.status 2>/dev/null | grep '"ip-address"' | cut -d'"' -f4 | head -n 1 || true)
        if [[ -n "$ip" ]]; then
          echo "$ip"
          return 0
        fi
      done
    fi
  fi

  echo ""
}

# Listar VMs con su ID numérico
list_vms() {
  get_vms_array

  echo -e "${C_BOLD}================================================================================${C_RESET}"
  echo -e "${C_BOLD}                   Máquinas Virtuales KVM / QEMU                                ${C_RESET}"
  echo -e "${C_BOLD}================================================================================${C_RESET}"

  if [[ ${#VMS[@]} -eq 0 ]]; then
    warn "No hay máquinas virtuales creadas en libvirt."
    return 0
  fi

  printf "${C_BOLD}%-5s %-26s %-14s %-28s${C_RESET}\n" "NUM" "NOMBRE" "ESTADO" "DIRECCIÓN IP"
  echo "--------------------------------------------------------------------------------"

  local idx=1
  for vm in "${VMS[@]}"; do
    local state
    state=$(virsh domstate "$vm" 2>/dev/null || echo "desconocido")
    local ip_str="Apagada"
    local color_state="$C_RED"

    if [[ "$state" =~ running|ejecución ]]; then
      color_state="$C_GREEN"
      local detected_ip
      detected_ip=$(detect_ip "$vm")
      if [[ -n "$detected_ip" ]]; then
        ip_str="${C_CYAN}${detected_ip}${C_RESET}"
      else
        ip_str="${C_YELLOW}Obteniendo IP (Instalando)...${C_RESET}"
      fi
    fi

    printf "${C_BOLD}[%d]${C_RESET}  %-26s ${color_state}%-14s${C_RESET} %b\n" "$idx" "$vm" "$state" "$ip_str"
    ((idx++))
  done
  echo "--------------------------------------------------------------------------------"
}

# Resolver número (1, 2, 3...) o nombre exacto a nombre de VM
resolve_vm() {
  local input="${1:-}"
  get_vms_array

  # Si es un número entero
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    local index=$((input - 1))
    if [[ $index -ge 0 && $index -lt ${#VMS[@]} ]]; then
      echo "${VMS[$index]}"
      return 0
    fi
  fi

  # Si coincide con un nombre directo
  for vm in "${VMS[@]}"; do
    if [[ "$vm" == "$input" ]]; then
      echo "$vm"
      return 0
    fi
  done

  return 1
}

# Asistente de selección interactiva por número
select_vm_prompt() {
  local prompt_title="${1:-Selecciona una máquina virtual}"
  get_vms_array

  if [[ ${#VMS[@]} -eq 0 ]]; then
    warn "No hay máquinas virtuales disponibles."
    return 1
  fi

  echo -e "\n${C_BOLD}${prompt_title}:${C_RESET}"
  local idx=1
  for vm in "${VMS[@]}"; do
    local state
    state=$(virsh domstate "$vm" 2>/dev/null || echo "desconocido")
    echo -e "  ${C_BOLD}[${idx}]${C_RESET} ${vm} (${state})"
    ((idx++))
  done
  echo -e "  ${C_BOLD}[0]${C_RESET} Cancelar"
  echo

  while true; do
    read -r -p "Ingresa el número [1-${#VMS[@]}] (o 0 para cancelar): " choice
    if [[ "$choice" == "0" || "$choice" == "q" || "$choice" == "cancel" ]]; then
      return 1
    fi
    local resolved
    if resolved=$(resolve_vm "$choice"); then
      echo "$resolved"
      return 0
    else
      warn "Número no válido. Elige entre 1 y ${#VMS[@]}."
    fi
  done
}

# Iniciar VM
start_vm() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM que deseas INICIAR") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  info "Iniciando '${C_BOLD}${target}${C_RESET}'..."
  virsh start "$target"
  success "'${target}' iniciada correctamente."
}

# Apagar VM (ACPI ordenado)
stop_vm() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM que deseas APAGAR") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  info "Enviando orden de apagado ordenado a '${C_BOLD}${target}${C_RESET}'..."
  virsh shutdown "$target"
  success "Orden de apagado enviada."
}

# Forzar apagado inmediato (destroy)
destroy_vm() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM para FORZAR APAGADO") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  warn "Forzando apagado inmediato de '${C_BOLD}${target}${C_RESET}'..."
  virsh destroy "$target" || true
  success "VM detenida."
}

# Conectar Visor Gráfico SPICE
open_viewer() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM para abrir VISOR GRÁFICO (SPICE)") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  if command -v virt-viewer &>/dev/null; then
    info "Abriendo virt-viewer para '${C_BOLD}${target}${C_RESET}'..."
    virt-viewer -c qemu:///system "$target" &
  else
    warn "virt-viewer no está instalado. Ejecuta: sudo ./prepare-environment.sh"
  fi
}

# Conectar Consola Serie
open_console() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM para CONSOLA SERIE") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  info "Conectando a la consola serie de '${C_BOLD}${target}${C_RESET}'..."
  echo -e "${C_YELLOW}Nota: Presiona 'Ctrl + ]' para salir de la consola.${C_RESET}"
  virsh console "$target"
}

# Consultar IP detallada
get_vm_ip() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM para consultar IP") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  info "Consultando IP para '${C_BOLD}${target}${C_RESET}'..."
  local ip
  ip=$(detect_ip "$target")
  if [[ -n "$ip" ]]; then
    echo -e "${C_GREEN}${C_BOLD}✔ Dirección IP de '${target}': ${C_CYAN}${ip}${C_RESET}"
  else
    warn "No se pudo obtener la IP de '${target}'."
    echo -e "Posibles causas:"
    echo -e "  • La máquina aún se está instalando o reiniciando."
    echo -e "  • El servicio qemu-guest-agent aún no ha arrancado dentro del sistema."
  fi
}

# ELIMINAR VM y sus discos (por número y confirmación sencilla con 's')
delete_vm() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    target=$(select_vm_prompt "Selecciona la VM que deseas ELIMINAR COMPLETAMENTE") || return 0
  else
    target=$(resolve_vm "$target") || { error "No se encontró la VM correspondiente a '$1'"; return 1; }
  fi

  echo
  warn "⚠️  ¿Confirmas que deseas ELIMINAR '${C_BOLD}${target}${C_RESET}' y BORRAR SU DISCO virtual?"
  read -r -p "Presiona 's' para confirmar (cualquier otra tecla cancela): " confirm_del
  if [[ "$confirm_del" =~ ^[sSyY]$ ]]; then
    info "Deteniendo máquina si está en ejecución..."
    virsh destroy "$target" 2>/dev/null || true
    info "Eliminando definición y archivos de disco asociados..."
    virsh undefine "$target" --remove-all-storage 2>/dev/null || virsh undefine "$target"
    success "Máquina virtual '${target}' y sus discos han sido eliminados correctamente."
  else
    info "Operación cancelada. No se eliminó nada."
  fi
}

# Diagnóstico de Red KVM / libvirt
diagnose_network() {
  echo -e "\n${C_BOLD}================================================================================${C_RESET}"
  echo -e "${C_BOLD}               Diagnóstico de Red KVM / libvirt (Health Check)                 ${C_RESET}"
  echo -e "${C_BOLD}================================================================================${C_RESET}"
  
  # 1. libvirtd
  if systemctl is-active libvirtd &>/dev/null || systemctl is-active virtqemud &>/dev/null; then
    echo -e "• Servicio libvirt:              ${C_GREEN}✔ Activo${C_RESET}"
  else
    echo -e "• Servicio libvirt:              ${C_RED}✖ Inactivo${C_RESET}"
  fi

  # 2. Red default
  if virsh net-info default 2>/dev/null | grep -E -i -q "(Active|Activo):[[:space:]]*(yes|sí)"; then
    echo -e "• Red libvirt 'default':         ${C_GREEN}✔ Activa (Autostart: Sí)${C_RESET}"
  else
    echo -e "• Red libvirt 'default':         ${C_RED}✖ Inactiva${C_RESET}"
  fi

  # 3. Interfaz virbr0
  if ip addr show virbr0 &>/dev/null; then
    local virbr0_ip
    virbr0_ip=$(ip -4 addr show virbr0 2>/dev/null | awk '/inet / {print $2}' || echo "Sin IP")
    echo -e "• Puente de red (virbr0):        ${C_GREEN}✔ Operativo (${virbr0_ip})${C_RESET}"
  else
    echo -e "• Puente de red (virbr0):        ${C_RED}✖ No encontrado${C_RESET}"
  fi

  # 4. Servidor DHCP / DNS (dnsmasq)
  if ss -ulpn 2>/dev/null | grep -q "virbr0:67"; then
    echo -e "• Servidor DHCP (dnsmasq:67):    ${C_GREEN}✔ Escuchando en virbr0${C_RESET}"
  else
    echo -e "• Servidor DHCP (dnsmasq:67):    ${C_YELLOW}⚠ No detectado en puerto 67${C_RESET}"
  fi

  # 5. IP Forwarding del kernel
  local ipf
  ipf=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
  if [[ "$ipf" == "1" ]]; then
    echo -e "• Enrutamiento (IPv4 Forward):   ${C_GREEN}✔ Habilitado (net.ipv4.ip_forward=1)${C_RESET}"
  else
    echo -e "• Enrutamiento (IPv4 Forward):   ${C_RED}✖ Deshabilitado${C_RESET}"
  fi

  # 6. Cortafuegos del host (nftables)
  if [[ -f /etc/nftables.conf ]] && grep -q "chain input" /etc/nftables.conf; then
    if grep -q "virbr" /etc/nftables.conf; then
      echo -e "• Cortafuegos (nftables):        ${C_GREEN}✔ Reglas para virbr* autorizadas${C_RESET}"
    else
      echo -e "• Cortafuegos (nftables):        ${C_RED}✖ BLOQUEANDO virbr* (falta regla en /etc/nftables.conf)${C_RESET}"
      echo -e "  ${C_YELLOW}→ Causa:${C_RESET} La política DROP bloquea el DHCP y el tráfico de KVM."
      echo -e "  ${C_YELLOW}→ Solución:${C_RESET} Ejecuta ${C_BOLD}sudo ./prepare-environment.sh${C_RESET} para corregirlo automáticamente."
    fi
  fi

  # 6. Tabla de asignaciones DHCP activas
  echo -e "\n${C_BOLD}Arrendamientos DHCP actuales de la red 'default':${C_RESET}"
  local leases
  leases=$(virsh net-dhcp-leases default 2>/dev/null || true)
  if echo "$leases" | grep -E -q '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then
    echo "$leases"
  else
    echo -e "${C_YELLOW}  (No hay IPs concedidas en este momento. Las VMs las solicitan al arrancar).${C_RESET}"
  fi

  echo -e "\n${C_CYAN}ℹ Sobre el aviso 'QEMU guest agent is not connected':${C_RESET}"
  echo -e "  Durante la instalación desatendida de Debian, el instalador no ejecuta el agente todavía."
  echo -e "  El agente se conecta automáticamente una vez que la máquina termina de instalarse y reinicia."
  echo -e "${C_BOLD}================================================================================${C_RESET}\n"
}

# Menú interactivo
interactive_menu() {
  while true; do
    echo
    list_vms
    echo
    echo -e "${C_BOLD}Acciones disponibles (selecciona con un número):${C_RESET}"
    echo -e "  ${C_GREEN}1)${C_RESET} Iniciar VM"
    echo -e "  ${C_YELLOW}2)${C_RESET} Apagar VM (ACPI ordenado)"
    echo -e "  ${C_RED}3)${C_RESET} Forzar apagado (inmediato)"
    echo -e "  ${C_CYAN}4)${C_RESET} Conectar Visor Gráfico (SPICE)"
    echo -e "  ${C_BLUE}5)${C_RESET} Conectar Consola Serie (texto)"
    echo -e "  ${C_MAGENTA}6)${C_RESET} Consultar IP de una VM"
    echo -e "  ${C_RED}7)${C_RESET} ${C_BOLD}Eliminar VM y sus discos virtuales${C_RESET}"
    echo -e "  ${C_WHITE}8)${C_RESET} Refrescar lista"
    echo -e "  ${C_CYAN}9)${C_RESET} 🔍 Diagnosticar Red KVM / libvirt"
    echo -e "  ${C_BOLD}0)${C_RESET} Volver al menú principal"
    echo
    read -r -p "Elige una acción [0-9]: " action_opt
    case "$action_opt" in
      1) start_vm ;;
      2) stop_vm ;;
      3) destroy_vm ;;
      4) open_viewer ;;
      5) open_console ;;
      6) get_vm_ip ;;
      7) delete_vm ;;
      8) continue ;;
      9) diagnose_network; read -r -p "Presiona Enter para continuar..." _ ;;
      0|q|exit) break ;;
      *) warn "Opción no válida." ;;
    esac
  done
}

# Despachador CLI
CMD="${1:-menu}"
ARG="${2:-}"

case "$CMD" in
  list) list_vms ;;
  ip) get_vm_ip "$ARG" ;;
  start) start_vm "$ARG" ;;
  stop) stop_vm "$ARG" ;;
  destroy) destroy_vm "$ARG" ;;
  delete|rm) delete_vm "$ARG" ;;
  viewer) open_viewer "$ARG" ;;
  console) open_console "$ARG" ;;
  net-check|diag) diagnose_network ;;
  menu|"") interactive_menu ;;
  *)
    echo "Uso: $0 [list | ip <num|nombre> | start <num|nombre> | stop <num|nombre> | destroy <num|nombre> | delete <num|nombre> | viewer <num|nombre> | console <num|nombre> | net-check]"
    ;;
esac

#!/usr/bin/env bash
# Debe ejecutarse como root (sudo o su -).
set -euo pipefail

# 1. Comprobar ejecución como root
test "$EUID" -eq 0 || {
  echo "Este script debe ejecutarse como root (sudo o su -)."
  exit 1
}

# 2. Determinar usuario objetivo
# - Si se ejecuta con sudo, SUDO_USER define el usuario original.
# - Si se ejecuta como root directamente, puede pasarse como argumento.
if [ -n "${SUDO_USER-}" ]; then
  TARGET_USER="$SUDO_USER"
elif [ $# -ge 1 ]; then
  TARGET_USER="$1"
else
  echo "Uso: $0 [usuario]
Ejecuta como root (sudo o su -). Si no usas sudo, especifica el usuario a configurar."
  exit 1
fi

echo "🔧 Usuario objetivo: $TARGET_USER"

# 3. Paquetes requeridos
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

# 4. Activar y arrancar libvirtd
echo "🔧 Habilitando y arrancando libvirtd"
systemctl enable --now libvirtd

# 5. Añadir usuario al grupo kvm
echo "🔧 Añadiendo $TARGET_USER al grupo kvm"
usermod -aG kvm "$TARGET_USER"

# 6. Editar /etc/sudoers
# Inserta debajo de la línea de root la entrada para TARGET_USER
echo "🔧 Editando /etc/sudoers para añadir '$TARGET_USER'"
# Hacer copia de seguridad
cp /etc/sudoers /etc/sudoers.bak
# Insertar usando sed
sed -i "/^root[[:space:]]\+ALL=(ALL:ALL) ALL/ a \
$TARGET_USER ALL=(ALL:ALL) ALL" /etc/sudoers
# Validar sintaxis
visudo -c

# 7. Mensaje final
cat <<EOF
✅ Entorno preparado para '$TARGET_USER'.
Dependencias: ${REQUIRED[*]}.
- '$TARGET_USER' añadido al grupo kvm.
- /etc/sudoers actualizado con privilegios equivalentes a root.

Ahora puedes ejecutar create-debian-vm.sh desde tu repositorio para crear la VM.
EOF mensaje final
cat <<EOF
✅ Entorno preparado para '$TARGET_USER'.
Dependencias: ${REQUIRED[*]}.
- '$TARGET_USER' añadido al grupo kvm.
- Sudo sin contraseña configurado en $SUDOERS_FILE.

Ahora puedes ejecutar create-debian-vm.sh desde tu repositorio para crear la VM.
EOF

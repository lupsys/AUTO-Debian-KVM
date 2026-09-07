# 🚀 AUTO-Debian-KVM

<div align="center">

![Debian](https://img.shields.io/badge/Debian-12%20(Bookworm)-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![KVM](https://img.shields.io/badge/KVM-QEMU-FF6600?style=for-the-badge&logo=linux&logoColor=white)
![Arch](https://img.shields.io/badge/Arch%20Linux-Supported-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-Supported-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-Supported-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Shell-Bash%205-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)

**Herramienta profesional para el aprovisionamiento 100% automatizado y desatendido de máquinas virtuales Debian en KVM / QEMU / libvirt.**

[Características](#-características) • [Instalación Rápida](#-instalación-rápida) • [Perfiles](#-perfiles-de-instalación) • [Uso CLI](#-uso-avanzado-por-línea-de-comandos) • [Gestión de VMs](#-gestión-de-vms) • [Compatibilidad](#-compatibilidad-multi-distro)

</div>

---

## ✨ Características

- ⚡ **Inyección Nativa en initrd (`--initrd-inject`)**: Olvídate de levantar servidores web locales, abrir puertos en firewalls o depender de URLs externas. El archivo `preseed.cfg` se inyecta directamente en la memoria del instalador.
- 🐧 **Compatibilidad Multi-Distro Universal**: Detecta automáticamente tu gestor de paquetes (**pacman**, **apt**, **dnf**, **zypper**), instala dependencias, configura grupos (`kvm`, `libvirt`) y valida la red virtual `default`.
- 🧩 **Perfiles Listos para Producción**:
  - **Server Minimal / Headless**: Servidor ultraligero con SSH y QEMU Guest Agent.
  - **Docker Ready**: Listo para contenedores con Docker Engine y Docker Compose preinstalados.
  - **Desktop XFCE**: Entorno de escritorio ligero con aceleración gráfica virtio y soporte de portapapeles bidireccional SPICE.
  - **Desktop GNOME**: Entorno gráfico moderno completo.
- 🔑 **Seguridad y Personalización**: Generación de contraseñas dinámicas, inyección opcional de tu clave SSH pública (`~/.ssh/id_rsa.pub`) y sudo sin contraseña configurable.
- 🎛️ **Menú TUI Interactivo + CLI Scriptable**: Úsalo mediante un menú visual asistido o automatiza despliegues en scripts con flags.
- 📊 **Gestor Integrado de VMs**: Consulta IPs activas en tiempo real vía DHCP/Guest-Agent, abre visores SPICE o consolas serie, y destruye VMs limpiando sus discos.

---

## 🚀 Instalación Rápida

### Opción 1: Clonar y Ejecutar (Recomendado)

```bash
git clone https://github.com/lupsys/AUTO-Debian-KVM.git
cd AUTO-Debian-KVM
chmod +x *.sh
./menu.sh
```

### Opción 2: Ejecución Directa en 1 Línea

```bash
curl -fsSL https://raw.githubusercontent.com/lupsys/AUTO-Debian-KVM/main/menu.sh | bash
```

---

## 🛠️ Paso Previo: Preparación del Entorno

Si es la primera vez que usas KVM en tu equipo, ejecuta el asistente para instalar y verificar los servicios de virtualización:

```bash
sudo ./prepare-environment.sh
```

Este script:
1. Comprueba que tu CPU soporte virtualización por hardware (**Intel VT-x** o **AMD-V**).
2. Instala los paquetes necesarios según tu distribución (**Arch**, **Debian/Ubuntu**, **Fedora**, **openSUSE**).
3. Habilita y arranca el servicio `libvirtd` (o demonios modulares `virtqemud`, `virtnetworkd`).
4. Añade tu usuario a los grupos `kvm` y `libvirt`.
5. Activa la red virtual NAT `default` en autostart.

---

## 🧩 Perfiles de Instalación

| Perfil | Descripción | RAM Sugerida | Disco Sugerido | Entorno Gráfico |
|---|---|---|---|---|
| `minimal` | Servidor limpio, rápido y eficiente (SSH, guest-agent, htop, curl, git) | 2048 MB | 10 GB | No (Consola serie/SPICE) |
| `docker` | Servidor con Docker Engine y Docker Compose preconfigurados | 3072 MB | 20 GB | No (Consola serie/SPICE) |
| `desktop-xfce` | Escritorio liviano XFCE4 con SPICE agent (portapapeles y resolución dinámica) | 4096 MB | 20 GB | Sí (SPICE / virt-viewer) |
| `desktop-gnome` | Escritorio completo GNOME | 4096 MB | 20 GB | Sí (SPICE / virt-viewer) |

---

## 💻 Uso Avanzado por Línea de Comandos (CLI)

Puedes automatizar la creación de máquinas virtuales sin confirmaciones interactivas usando `create-debian-vm.sh`:

```bash
./create-debian-vm.sh [OPCIONES]
```

### Parámetros Disponibles

| Opción | Descripción | Valor por Defecto |
|---|---|---|
| `-n, --name NOMBRE` | Nombre único de la máquina virtual | `debian-MMDD-HHMM` |
| `-p, --profile PERFIL` | `minimal`, `docker`, `desktop-xfce`, `desktop-gnome` | `minimal` |
| `-m, --ram MB` | Cantidad de memoria RAM en MB | `2048` (Server) / `4096` (Desktop) |
| `-c, --cpus NUM` | Número de núcleos de CPU (vCPUs) | `2` |
| `-d, --disk GB` | Tamaño del disco duro virtual en GB (mínimo 10GB) | `10` (Server) / `20` (Desktop) |
| `-u, --user USUARIO` | Nombre del usuario principal | `debian` |
| `--password PASS` | Contraseña del usuario | `debian1234` |
| `--root-password PASS`| Contraseña de superusuario (root) | `debian1234` |
| `-k, --ssh-key RUTA` | Ruta a la clave pública SSH para acceso sin clave | *(Ninguna)* |
| `--nopasswd-sudo` | Conceder sudo sin pedir contraseña | `false` |
| `--dry-run` | Muestra el comando virt-install y el preseed generado sin ejecutar nada | `false` |
| `-y, --non-interactive` | No pedir confirmación en terminal | `false` |

### Ejemplos Prácticos

**Desplegar un nodo Docker con tu clave SSH:**
```bash
./create-debian-vm.sh \
  --name debian-docker \
  --profile docker \
  --ram 4096 \
  --cpus 4 \
  --disk 30 \
  --ssh-key ~/.ssh/id_rsa.pub \
  --nopasswd-sudo \
  -y
```

**Desplegar un escritorio ligero XFCE para pruebas:**
```bash
./create-debian-vm.sh \
  --name debian-xfce \
  --profile desktop-xfce \
  --ram 4096 \
  --disk 30 \
  -y
```

---

## 📊 Gestión de VMs

Incluye la herramienta `manage-vms.sh` para administrar el ciclo de vida de tus VMs:

```bash
# Listar todas las VMs y consultar sus IPs activas
./manage-vms.sh list

# Iniciar o apagar una máquina
./manage-vms.sh start debian-docker
./manage-vms.sh stop debian-docker

# Abrir el visor gráfico SPICE
./manage-vms.sh viewer debian-xfce

# Conectar a la consola serie
./manage-vms.sh console debian-docker

# Consultar la IP asignada por DHCP
./manage-vms.sh ip debian-docker

# Eliminar una VM y borrar su archivo .qcow2
./manage-vms.sh delete debian-docker
```

También puedes ejecutar `./manage-vms.sh` sin argumentos para usar el menú interactivo de gestión.

---

## 🌐 Compatibilidad Multi-Distro

Probado y certificado en:
- **Arch Linux / Manjaro / EndeavourOS** (`pacman`)
- **Debian 11 / 12** (`apt`)
- **Ubuntu 20.04 / 22.04 / 24.04** (`apt`)
- **Fedora 38 / 39 / 40 / 41** (`dnf`)
- **openSUSE Tumbleweed / Leap** (`zypper`)

---

## ❓ Preguntas Frecuentes

<details>
<summary><b>¿Dónde se guardan las contraseñas generadas?</b></summary>
Al finalizar la creación de cada VM, se genera un archivo protegido con permisos 600 llamado <code>creds-NOMBRE_VM.txt</code> en el directorio raíz del proyecto con el usuario, contraseña y detalles de conexión.
</details>

<details>
<summary><b>¿Cómo me conecto por SSH a la VM creada?</b></summary>
Una vez terminada la instalación, consulta la IP asignada con:
<pre><code>./manage-vms.sh ip NOMBRE_VM</code></pre>
Y conéctate directamente:
<pre><code>ssh debian@IP_OBTENIDA</code></pre>
</details>

<details>
<summary><b>¿Por qué usar inyección en initrd en lugar de servidor HTTP?</b></summary>
La inyección nativa en initrd no requiere abrir puertos de red en el host ni levantar servicios auxiliares de Python. Es completamente inmune a bloqueos por firewalls locales o problemas de resolución DNS en la fase inicial del instalador.
</details>

---

## 📄 Licencia

Distribuido bajo la Licencia MIT. Consulta el archivo de licencia para más detalles.

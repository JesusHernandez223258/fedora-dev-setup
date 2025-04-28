#!/usr/bin/env bash

# ==============================================================================
# Script de Configuración Automatizada para Fedora (Mejorado)
# ==============================================================================
# Este script automatiza la configuración inicial, instalación de repositorios,
# herramientas de desarrollo y aplicaciones comunes en Fedora.
# Incorpora mejoras como detección de hardware, manejo de errores, logs
# y confirmaciones interactivas.
#
# Uso: sudo ./setup.sh <fase>
# Fases: phase1, phase2, phase3, phase4 (opcional)
# Para ver la secuencia de fases: ./setup.sh all
# ==============================================================================

# --- 1. Configuración Inicial y Opciones Seguras ---
# Establecer opciones para hacer el script más robusto:
# -e: Salir inmediatamente si un comando falla (devuelve un estado de salida distinto de cero).
# -u: Tratar las variables no definidas como un error y salir inmediatamente.
# -o pipefail: Si cualquier comando en un pipeline falla, todo el pipeline falla.
set -euo pipefail

# Capturar errores: Ejecutar una función si ocurre un error (cualquier comando sale con != 0)
# $LINENO es el número de línea donde ocurrió el error.
trap 'log_error "Script ha fallado en la línea $LINENO"' ERR

# Capturar señales de salida/interrupción: Limpiar si el script termina inesperadamente.
cleanup() {
    log_warn "Terminando script, limpiando recursos si es necesario..."
    # Añadir aquí comandos para limpiar archivos temporales, detener servicios, etc.
    # En este script actual, no se crean recursos temporales que necesiten limpieza elaborada.
}
trap cleanup EXIT SIGINT SIGTERM

# --- 2. Variables Globales y Rutas ---
# Identifica al usuario que inició sudo, o el usuario actual si no se usa sudo.
# Esto es crucial para operaciones que deben ejecutarse como el usuario normal.
TARGET_USER="${SUDO_USER:-$(whoami)}"
# Directorio donde está el script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# Directorio para archivos de configuración del usuario.
USER_CONFIG_DIR="$SCRIPT_DIR/config/user"
# Archivo de configuración de DNF local.
DNF_CONFIG_FILE="$SCRIPT_DIR/config/dnf/dnf.conf"
# Archivo de log. Usamos /var/log que requiere permisos de root para escritura.
# Considera usar un directorio en el HOME del usuario si no quieres requerir root para el log.
LOGFILE="/var/log/fedora_setup_$(date +%Y%m%d_%H%M%S).log" # Nombre de log único por ejecución.

# --- 3. Estilo de Salida y Colores ---
# Colores ANSI para mensajes. Usamos '-e' en echo para interpretar escapes.
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m' # Restablece el color al por defecto

# Funciones de logging mejoradas: Imprimen en consola y registran en el archivo de log.
# Usamos 'tee -a' para mostrar en pantalla y anexar al archivo.
# Añadimos timestamp a cada entrada del log.
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${COLOR_GREEN}$1${COLOR_RESET}" | tee -a "$LOGFILE"
}
log_warn() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [WARN] ${COLOR_YELLOW}$1${COLOR_RESET}" | tee -a "$LOGFILE" >&2 # Envía warnings a stderr
}
log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${COLOR_RED}$1${COLOR_RESET}" | tee -a "$LOGFILE" >&2 # Envía errores a stderr
}
log_debug() {
    # Activar debug con set -x para ver estas líneas
    # echo -e "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $1" | tee -a "$LOGFILE" >&2
    : # No hace nada por defecto
}

# --- 4. Validaciones Iniciales ---
# Crear el archivo de log si no existe (se crea automáticamente con tee -a, pero esto asegura el directorio).
mkdir -p "$(dirname "$LOGFILE")" || log_error "No se pudo crear el directorio para el archivo de log $LOGFILE. Verifique permisos."

# Validar que el script se ejecute como root para las fases que lo requieren.
check_root() {
    if [[ $EUID -ne 0 ]]; then
       log_error "Este script (o esta fase) debe ejecutarse con sudo."
       log_error "Uso: sudo ./setup.sh <fase>"
       exit 1
    fi
    log_info "Ejecutando con permisos de root. Procediendo..."
}

# Validar que comandos esenciales están disponibles.
check_dependencies() {
    local cmds=("dnf" "sudo" "git" "curl" "systemctl" "tee" "date" "grep" "sed")
    local missing=()
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Comandos necesarios no encontrados: ${missing[*]}"
        log_error "Por favor, asegúrese de que estos comandos estén instalados y en su PATH."
        exit 1
    fi
    log_info "Dependencias básicas encontradas."
}

# Validar la existencia de archivos de configuración locales.
check_config_files() {
    log_info "Verificando archivos de configuración locales en $SCRIPT_DIR..."
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        log_warn "Directorio de configuración de usuario $USER_CONFIG_DIR no encontrado. Algunas configuraciones pueden ser omitidas."
    fi
     if [ ! -f "$DNF_CONFIG_FILE" ]; then
        log_warn "Archivo de configuración de DNF local $DNF_CONFIG_FILE no encontrado. Los ajustes de DNF locales serán omitidos."
    fi
    log_info "Verificación de archivos de configuración completada."
}


# --- 5. Detección de Hardware ---
detect_hardware() {
    log_info "Detectando hardware..."
    # Detección de GPU
    GPU_TYPE="Unknown"
    if lspci | grep -i 'vga.*nvidia' &>/dev/null; then
        GPU_TYPE="Nvidia"
        log_info "GPU detectada: Nvidia."
    elif lspci | grep -i 'vga.*advanced micro devices' &>/dev/null || lspci | grep -i 'vga.*amd/ati' &>/dev/null; then
        GPU_TYPE="AMD"
        log_info "GPU detectada: AMD."
    elif lspci | grep -i 'vga.*intel' &>/dev/null; then
        GPU_TYPE="Intel"
        log_info "GPU detectada: Intel Integrada."
    else
        log_warn "No se pudo detectar un tipo de GPU conocido (Nvidia, AMD, Intel)."
    fi

    # Detección de soporte de virtualización por hardware (VT-x/AMD-V)
    VIRT_SUPPORT="False"
    if egrep -q '(vmx|svm)' /proc/cpuinfo; then
        VIRT_SUPPORT="True"
        log_info "Soporte de virtualización (VT-x/AMD-V) detectado en la CPU."
    else
        log_warn "Soporte de virtualización por hardware (VT-x/AMD-V) no detectado en la CPU."
    fi

    log_info "Detección de hardware completada. GPU: $GPU_TYPE, Virtualización HW: $VIRT_SUPPORT."
}

# --- 6. Funciones para cada fase de instalación ---

phase1_initial_setup() {
    log_info "=== Fase 1: Configuración Inicial y Repositorios ==="
    check_root # Asegurarse de que se ejecuta con root.

    log_info "Aplicando ajustes en /etc/dnf/dnf.conf..."
    if [ -f "$DNF_CONFIG_FILE" ]; then
        # Leer el archivo local de DNF y aplicar sus configuraciones al archivo del sistema.
        # Esto es un ejemplo simple: solo añade líneas si no existen.
        # Una implementación más robusta usaría sed para reemplazar valores existentes en [main].
        log_info "Aplicando max_parallel_downloads=10..."
        grep -qxF 'max_parallel_downloads=10' /etc/dnf/dnf.conf || echo 'max_parallel_downloads=10' | tee -a /etc/dnf/dnf.conf > /dev/null || log_warn "Fallo al agregar max_parallel_downloads."
        log_info "Aplicando deltarpm=True..."
        grep -qxF 'deltarpm=True' /etc/dnf/dnf.conf || echo 'deltarpm=True' | tee -a /etc/dnf/dnf.conf > /dev/null || log_warn "Fallo al agregar deltarpm."
        log_info "Aplicando defaultyes=True..." # ¡Advertencia! defaultyes puede ser peligroso. Considera removerlo o hacerlo opcional.
        grep -qxF 'defaultyes=True' /etc/dnf/dnf.conf || echo 'defaultyes=True' | tee -a /etc/dnf/dnf.conf > /dev/null || log_warn "Fallo al agregar defaultyes."
        log_info "Ajustes de DNF aplicados (añadidos si no existían)."
    else
        log_warn "No se encontró el archivo de configuración de DNF local en $DNF_CONFIG_FILE. Saltando ajuste de DNF."
    fi

    log_info "Instalando herramientas básicas y plugins DNF..."
    # dn f install -y ... || log_error "Fallo al instalar herramientas básicas." # Set -e ya lo maneja
    dnf install -y dnf-plugins-core unzip p7zip p7zip-plugins unrar fastfetch git

    log_info "Habilitando repositorios RPMFusion..."
    # dn f install -y ... || log_error "Fallo al habilitar RPMFusion." # Set -e ya lo maneja
    dnf install -y \
      https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

    log_info "Actualizando grupo core de DNF..."
    dnf group upgrade -y core # Dnf core upgrade
    if command -v dnf5 &>/dev/null; then
        log_info "Actualizando grupo core de DNF5 (si está disponible)..."
        dnf5 group upgrade -y core # Dnf5 core upgrade if available
    fi

    log_info "Habilitando repositorios Tainted de RPMFusion..."
    # dn f install -y ... || log_error "Fallo al habilitar RPMFusion Tainted." # Set -e ya lo maneja
    dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

    log_info "Instalando COPR CLI..."
    # dn f install -y ... || log_error "Fallo al instalar COPR CLI." # Set -e ya lo maneja
    dnf install -y copr-cli

    log_info "Habilitando repositorio Terra (Nota: Se usa --nogpgcheck - considera añadir la clave GPG)..."
    # Buscar la clave GPG de Terra e importarla sería lo ideal en lugar de --nogpgcheck
    # dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' -y terra-release || log_error "Fallo al habilitar repositorio Terra." # Set -e ya lo maneja
     dnf install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' -y terra-release


    log_info "Habilitando soporte Flatpak y Snap..."
    # dn f install -y snapd || log_error "Fallo al instalar snapd." # Set -e ya lo maneja
    dnf install -y snapd

    # Habilitar y iniciar el servicio snapd
    log_info "Habilitando e iniciando servicio snapd..."
    systemctl enable --now snapd || log_warn "No se pudo habilitar/iniciar snapd. Intenta 'sudo systemctl enable --now snapd' y 'sudo systemctl start snapd' manualmente."
    systemctl status snapd --no-pager || log_warn "snapd service no está activo. Intenta 'sudo systemctl start snapd' manualmente."
    # Esperar un poco por si snapd necesita inicializarse
    sleep 5
    # snapd socket para --classic snaps
    log_info "Habilitando e iniciando snapd.socket..."
    systemctl enable --now snapd.socket || log_warn "No se pudo habilitar/iniciar snapd.socket. Intenta 'sudo systemctl enable --now snapd.socket' y 'sudo systemctl start snapd.socket' manualmente."


    # Añadir flathub remote como el usuario objetivo (flatpak remote-add corre como usuario)
    log_info "Añadiendo remote de Flathub para el usuario '$TARGET_USER'..."
    # sudo -u "$TARGET_USER" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || log_warn "Fallo al añadir remote de Flathub." # Set -e no funciona bien con sudo -u pipe
     if ! sudo -u "$TARGET_USER" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
         log_warn "Fallo al añadir remote de Flathub. Verifica si flatpak está instalado o si el usuario $TARGET_USER existe y tiene permisos."
     fi
    log_info "Soporte Flatpak y Snap habilitado (si los servicios se iniciaron correctamente)."

    log_info "Realizando actualización completa del sistema y grupos..."
    dnf upgrade -y --refresh # || log_error "Fallo durante dnf upgrade --refresh." # Set -e
    # Excluimos este plugin que a veces causa conflictos
    dnf groupupdate -y core --exclude=PackageKit-gstreamer-plugin # || log_error "Fallo durante dnf groupupdate core." # Set -e
    log_info "Actualización completa del sistema realizada."

    # 7. Validar acción peligrosa: Actualizar Firmware
    log_warn "La siguiente acción actualizará el firmware de tu sistema usando fwupdmgr."
    read -r -p "¿Desea proceder con la actualización del firmware? [S/n]: " confirm_fw
    confirm_fw=${confirm_fw:-S} # Default a 'S' si se presiona Enter

    if [[ "$confirm_fw" =~ ^[Ss]$ ]]; then
        log_info "Actualizando firmware del sistema..."
        fwupdmgr refresh --force # || log_error "Fallo al refrescar fwupdmgr." # Set -e
        fwupdmgr update -y # || log_error "Fallo al actualizar firmware." # Set -e
        log_info "Actualización de firmware completada (si había actualizaciones disponibles)."
    else
        log_info "Actualización de firmware cancelada por el usuario."
    fi

    log_info "=== Fin de la Fase 1 ==="
    log_warn "Por favor, ${COLOR_RED}REINICIA${COLOR_YELLOW} tu sistema ahora para que los cambios en los repositorios y el firmware surtan efecto correctamente."
    log_warn "Después de reiniciar, ejecuta este script nuevamente con el argumento 'phase2':"
    log_warn "sudo ./setup.sh phase2"
    exit 0 # Salir para forzar el reinicio
}

phase2_system_dev_base() {
    log_info "=== Fase 2: Soporte del Sistema y Entorno de Desarrollo Base ==="
    check_root # Asegurarse de que se ejecuta con root.
    detect_hardware # Ejecutar detección de hardware para esta fase.

    # 8. Detección de Hardware y Validación: Instalar Drivers (Nvidia - Opcional/Hardware específico)
    log_info "Instalando drivers (Nvidia, Multimedia). Nota: Los drivers Nvidia son específicos de hardware."
    if [ "$GPU_TYPE" == "Nvidia" ]; then
        log_warn "Se detectó hardware Nvidia. La siguiente acción instalará los drivers propietarios."
        read -r -p "¿Desea instalar los drivers propietarios de Nvidia? (Esto requiere los repos RPMFusion instalados en Fase 1 y puede requerir Secure Boot) [S/n]: " install_nvidia
        install_nvidia=${install_nvidia:-S}

        if [[ "$install_nvidia" =~ ^[Ss]$ ]]; then
            log_info "Instalando drivers y soporte Nvidia..."
            # dnf install -y ... || log_error "Fallo al instalar drivers Nvidia." # Set -e
            dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-power vulkan xorg-x11-drv-nvidia-cuda-libs
            log_info "Habilitando servicios de suspensión/resumen de Nvidia..."
            systemctl enable --now nvidia-{suspend,resume,hibernate} || log_warn "No se pudieron habilitar los servicios de suspend/resume de Nvidia."
            log_info "Drivers y soporte Nvidia instalados (requiere reinicio para cargar el módulo del kernel)."
        else
            log_info "Instalación de drivers Nvidia cancelada por el usuario."
        fi
    elif [ "$GPU_TYPE" == "AMD" ]; then
        log_info "Se detectó hardware AMD. Los drivers de código abierto ya están incluidos en el kernel y Mesa."
        log_info "Instalando firmware AMD adicional desde rpmfusion-nonfree-tainted..."
        dnf --repo=rpmfusion-nonfree-tainted install -y amd-gpu-firmware || log_warn "Fallo al instalar firmware AMD adicional."
    elif [ "$GPU_TYPE" == "Intel" ]; then
         log_info "Se detectó hardware Intel. Los drivers de código abierto ya están incluidos en el kernel y Mesa."
         log_info "Instalando intel-media-driver para aceleración de video..."
         dnf install -y intel-media-driver || log_warn "Fallo la instalación de intel-media-driver. Ignorando si no tienes hardware Intel compatible."
    else
        log_warn "No se detectó hardware gráfico específico para instalar drivers adicionales (Nvidia/AMD/Intel)."
    fi


    log_info "Instalando Soporte Multimedia y Codecs..."
    log_info "Cambiando a FFMPEG completo..."
    dnf swap -y ffmpeg-free ffmpeg --allowerasing # || log_error "Fallo al swappear FFMPEG." # Set -e
    log_info "Actualizando grupo multimedia..."
    # Actualiza el grupo multimedia, excluyendo el plugin conflictivo
    dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin # || log_error "Fallo durante dnf update @multimedia." # Set -e
    log_info "Instalando grupo sound-and-video..."
    dnf group install -y sound-and-video # Instalar paquetes de sonido y video complementarios # || log_error "Fallo al instalar grupo sound-and-video." # Set -e
    log_info "Instalando drivers multimedia específicos (VAAPI)..."
    # Drivers multimedia específicos (Nvidia VAAPI - solo si no es Intel o AMD, o si Nvidia drivers fueron instalados)
    if [ "$GPU_TYPE" == "Nvidia" ] && [[ "$install_nvidia" =~ ^[Ss]$ ]]; then # Solo instalar si es Nvidia y se instalaron drivers
         log_info "Instalando libva-nvidia-driver..."
         dnf install -y libva-nvidia-driver || log_warn "Fallo la instalación de libva-nvidia-driver. Ignorando si no tienes hardware Nvidia compatible."
    fi
     # Firmware adicional de rpmfusion-nonfree-tainted (excepto AMD ya manejado)
    if [ "$GPU_TYPE" != "AMD" ]; then
        log_info "Instalando firmware adicional (no-AMD) desde rpmfusion-nonfree-tainted..."
        dnf --repo=rpmfusion-nonfree-tainted install -y "*-firmware" || log_warn "Fallo al instalar firmware adicional."
    fi
    log_info "Soporte multimedia y codecs instalados."

    log_info "Instalando Grupos de Desarrollo y Sistema recomendados..."
    # dnf group install -y ... || log_error "Fallo al instalar grupos de software." # Set -e
    dnf group install -y admin-tools c-development desktop-accessibility development-tools system-tools python-science vlc

    # 8. Detección de Hardware: Soporte de Virtualización (KVM/QEMU/libvirt)
    log_info "Instalando soporte de virtualización (KVM/QEMU/libvirt)..."
    if [ "$VIRT_SUPPORT" == "True" ]; then
         log_info "Se detectó soporte de virtualización por hardware (VT-x/AMD-V). Instalando paquetes de virtualización."
         # dnf install -y @virtualization ... || log_error "Fallo al instalar paquetes de virtualización." # Set -e
         dnf install -y @virtualization qemu-kvm-core libvirt virt-install cockpit-machines guestfs-tools
    else
         log_warn "No se detectó soporte de virtualización por hardware (VT-x/AMD-V). Aun así, se instalarán los paquetes de virtualización, pero el rendimiento puede ser limitado (uso de emulación)."
         dnf install -y @virtualization qemu-kvm-core libvirt virt-install cockpit-machines guestfs-tools
    fi

    log_info "Habilitando e iniciando servicio libvirtd..."
    systemctl enable --now libvirtd || log_warn "Fallo al habilitar/iniciar libvirtd. Intenta 'sudo systemctl enable --now libvirtd' y 'sudo systemctl start libvirtd' manualmente."

    log_info "Añadiendo usuario '$TARGET_USER' al grupo libvirt..."
    # Verificar si el usuario ya pertenece al grupo
    if groups "$TARGET_USER" | grep -q '\blibvirt\b'; then
        log_info "El usuario '$TARGET_USER' ya pertenece al grupo 'libvirt'. Saltando adición."
    else
        # groupadd docker &>/dev/null # Este es el de docker, el de libvirt ya existe.
        usermod -aG libvirt "$TARGET_USER" || log_warn "Fallo al añadir '$TARGET_USER' al grupo 'libvirt'."
        log_info "Usuario '$TARGET_USER' añadido al grupo 'libvirt'."
        log_warn "Recuerda que deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} para que la pertenencia al grupo libvirt surta efecto."
    fi


    log_info "Instalando Docker Engine y Componentes..."
    # Asumimos que el repo de Docker se añadió en Fase 1 si era necesario (aunque el script actual no lo añade explícitamente).
    # Si el repo de Docker oficial es necesario, debería añadirse aquí o en fase 1.
    # El script actual instala docker-ce desde los repos de Fedora/RPMFusion si está disponible ahí.
    # Para el repo oficial de docker:
    # dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || log_warn "Fallo al añadir repo de Docker oficial."
    # dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log_error "Fallo al instalar Docker Engine." # Set -e
     dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "Habilitando e iniciando servicio docker..."
    systemctl enable --now docker || log_warn "Fallo al habilitar/iniciar docker. Intenta 'sudo systemctl enable --now docker' y 'sudo systemctl start docker' manualmente."

    log_info "Añadiendo usuario '$TARGET_USER' al grupo docker..."
     if groups "$TARGET_USER" | grep -q '\bdocker\b'; then
        log_info "El usuario '$TARGET_USER' ya pertenece al grupo 'docker'. Saltando adición."
    else
        groupadd docker &>/dev/null # Asegurarse de que el grupo existe (sin error si ya existe)
        usermod -aG docker "$TARGET_USER" || log_warn "Fallo al añadir '$TARGET_USER' al grupo 'docker'."
        log_info "Usuario '$TARGET_USER' añadido al grupo 'docker'."
        log_warn "Recuerda que deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} para que la pertenencia al grupo docker surta efecto y puedas usar 'docker' sin sudo."
    fi

    log_info "Instalando Java (OpenJDK), Maven y Ant+Ivy..."
    dnf install -y java-devel maven ant apache-ivy # || log_error "Fallo al instalar Java/Maven/Ant." # Set -e

    log_info "Instalando Golang..."
    dnf install -y golang # || log_error "Fallo al instalar Golang." # Set -e
    log_info "Configurando GOPATH y PATH para Golang para el usuario '$TARGET_USER'..."
    # Determinar el archivo de perfil del usuario
    PROFILE_FILE="/home/$TARGET_USER/.bashrc"
    if [ -f "/home/$TARGET_USER/.zshrc" ]; then
        PROFILE_FILE="/home/$TARGET_USER/.zshrc"
    fi
    log_info "Usando archivo de perfil: $PROFILE_FILE"

    # Crear directorio go para el usuario y configurar GOPATH/PATH de forma idempotente.
    sudo -u "$TARGET_USER" mkdir -p "$HOME/go" || log_warn "Fallo al crear directorio $HOME/go para el usuario $TARGET_USER."
    if ! sudo -u "$TARGET_USER" grep -q 'export GOPATH=' "$PROFILE_FILE"; then
        echo 'export GOPATH=$HOME/go' | sudo tee -a "$PROFILE_FILE" > /dev/null || log_warn "Fallo al configurar GOPATH en $PROFILE_FILE."
    fi
     if ! sudo -u "$TARGET_USER" grep -q 'export PATH=.*$GOPATH/bin' "$PROFILE_FILE"; then
        echo 'export PATH=$PATH:$GOPATH/bin' | sudo tee -a "$PROFILE_FILE" > /dev/null || log_warn "Fallo al configurar PATH para Go en $PROFILE_FILE."
    fi
    log_info "GOPATH y PATH para Golang configurados para el usuario '$TARGET_USER'."
    log_warn "Deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} (o hacer 'source $PROFILE_FILE') para que los cambios en GOPATH/PATH surtan efecto."


    log_info "Instalando Node.js y Yarn..."
    dnf install -y nodejs yarnpkg # || log_error "Fallo al instalar Node.js/Yarn." # Set -e
    log_info "Configurando directorio global de npm y PATH para el usuario '$TARGET_USER'..."
    # Crear directorio global de npm para el usuario y configurar prefix/PATH de forma idempotente.
    sudo -u "$TARGET_USER" mkdir -p "$HOME/.npm-global" || log_warn "Fallo al crear directorio $HOME/.npm-global para el usuario $TARGET_USER."
    # Configurar prefix para npm para el usuario (debe correr como el usuario)
    sudo -u "$TARGET_USER" npm config set prefix "$HOME/.npm-global" || log_warn "Fallo al configurar prefix de npm para el usuario $TARGET_USER."
    # Añadir el directorio global de npm al PATH en el archivo de perfil del usuario
    if ! sudo -u "$TARGET_USER" grep -q 'export PATH=.*\.npm-global/bin' "$PROFILE_FILE"; then
        echo 'export PATH=~/.npm-global/bin:$PATH' | sudo tee -a "$PROFILE_FILE" > /dev/null || log_warn "Fallo al configurar PATH para npm en $PROFILE_FILE."
    fi
    log_info "Directorio global de npm y PATH configurados para el usuario '$TARGET_USER'."
     log_warn "Deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} (o hacer 'source $PROFILE_FILE') para que los cambios en PATH surtan efecto."


    log_info "Instalando Bun (descargando script de internet)..."
    # NOTA: Descargar y ejecutar scripts directamente de internet es una práctica con riesgos de seguridad.
    # Es preferible descargar el script, revisarlo y luego ejecutarlo.
    if command -v bun &>/dev/null; then
        log_info "Bun ya parece estar instalado. Saltando instalación."
    else
        log_warn "Se procederá a descargar y ejecutar el script de instalación de Bun de bun.sh."
        read -r -p "¿Desea continuar con la instalación de Bun? [S/n]: " confirm_bun
        confirm_bun=${confirm_bun:-S}
        if [[ "$confirm_bun" =~ ^[Ss]$ ]]; then
             # Ejecutar el script de instalación de Bun como el usuario objetivo
             # El script de Bun gestiona su propio PATH
             if sudo -u "$TARGET_USER" curl -fsSL https://bun.sh/install | bash; then
                 log_info "Bun instalado (si el script se ejecutó correctamente)."
                 log_warn "El instalador de Bun intenta añadirlo a tu PATH. Deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} (o abrir una nueva terminal) para que el comando 'bun' esté disponible."
             else
                 log_warn "Fallo en la ejecución del script de instalación de Bun."
             fi
        else
            log_info "Instalación de Bun cancelada por el usuario."
        fi
    fi

    log_info "=== Fin de la Fase 2 ==="
    log_warn "La instalación de la base del sistema y entorno de desarrollo ha finalizado."
    log_warn "Es ${COLOR_RED}MUY RECOMENDABLE${COLOR_YELLOW} que ahora ${COLOR_RED}CIERRES TU SESIÓN ACTUAL${COLOR_YELLOW} (gráfica o de terminal) y vuelvas a iniciarla."
    log_warn "Esto es necesario para que los cambios en los grupos (docker, libvirt) y las variables de entorno (PATH para Go, Node/npm, Bun) surtan efecto."
    log_warn "Después de re-loguearte, ejecuta este script nuevamente con el argumento 'phase3' para configurar la terminal y las apps:"
    log_warn "sudo ./setup.sh phase3"
    exit 0
}

phase3_terminal_apps() {
    log_info "=== Fase 3: Configuración de Terminal y Aplicaciones ==="
    # Esta fase incluye la configuración de usuario y Flatpaks, que idealmente corren como usuario normal.
    # Sin embargo, para simplificar el manejo de sudo, el script maestro puede correr con sudo
    # y usar 'sudo -u $TARGET_USER' para los comandos de usuario.
    check_root # Asegurarse de que se ejecuta con root.

    log_info "Configurando terminal (Zsh, Oh My Zsh, Powerlevel10k) para el usuario '$TARGET_USER'..."

    # Instalar Zsh y Git si no se hizo en Fase 2 (o por si acaso)
    log_info "Instalando Zsh y Git (si no están ya instalados)..."
    dnf install -y zsh git # || log_error "Fallo al instalar Zsh/Git." # Set -e

    # 9. Validación de acción peligrosa: Cambiar shell por defecto
    log_warn "Se procederá a cambiar la shell por defecto del usuario '$TARGET_USER' a Zsh."
    read -r -p "¿Desea cambiar la shell por defecto a Zsh? [S/n]: " confirm_chsh
    confirm_chsh=${confirm_chsh:-S}

    if [[ "$confirm_chsh" =~ ^[Ss]$ ]]; then
        log_info "Cambiando shell por defecto para el usuario '$TARGET_USER' a $(which zsh)..."
        # Verificar si Zsh está en /etc/shells
        if ! grep "$(which zsh)" /etc/shells &>/dev/null; then
            log_warn "$(which zsh) no está listado en /etc/shells. Añadiéndolo temporalmente..."
            echo "$(which zsh)" | tee -a /etc/shells > /dev/null || log_warn "Fallo al añadir Zsh a /etc/shells. chsh puede fallar."
        fi
        # chsh requiere que la shell esté en /etc/shells y a menudo no funciona bien con sudo -u para cambiar la propia shell
        # Es mejor instruir al usuario o ejecutarlo como root si se conoce la contraseña del usuario
        # La forma más segura es que el usuario lo ejecute manualmente.
        log_warn "Para usar Zsh como tu shell por defecto, ejecuta ${COLOR_GREEN}manualmente${COLOR_YELLOW} después de que el script termine:"
        log_warn "${COLOR_GREEN}chsh -s \$(which zsh)${COLOR_YELLOW}"
        log_warn "Después de ejecutar 'chsh', deberás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} para que el cambio surta efecto."
        # Si realmente queremos automatizarlo con sudo:
        # log_info "Cambiando shell con sudo chsh..."
        # chsh -s "$(which zsh)" "$TARGET_USER" || log_warn "Fallo al cambiar la shell por defecto con chsh. Es posible que debas ejecutar 'chsh -s $(which zsh)' manualmente."
    else
        log_info "Cambio de shell por defecto a Zsh cancelado por el usuario."
    fi


    # Configurar Oh My Zsh y Powerlevel10k para el usuario
    OHMYZSH_DIR="/home/$TARGET_USER/.oh-my-zsh"
    P10K_THEME_DIR="$OHMYZSH_DIR/custom/themes/powerlevel10k"
    TARGET_USER_HOME="/home/$TARGET_USER"

    log_info "Configurando estructura básica de Oh My Zsh en $TARGET_USER_HOME..."
    # Usar sudo con la opción -H para establecer HOME correctamente
    sudo -H -u "$TARGET_USER" mkdir -p "$OHMYZSH_DIR/custom/themes" || log_warn "Fallo al crear directorios de Oh My Zsh."
    sudo -H -u "$TARGET_USER" mkdir -p "$OHMYZSH_DIR/custom/plugins" || log_warn "Fallo al crear directorios de Oh My Zsh."

    log_info "Clonando tema Powerlevel10k en $P10K_THEME_DIR..."
    if [ ! -d "$P10K_THEME_DIR" ]; then
        # Usar sudo con la opción -H para establecer HOME correctamente para git clone
        if sudo -H -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_THEME_DIR"; then
            log_info "Powerlevel10k clonado."
        else
            log_warn "Fallo al clonar Powerlevel10k. Verifique la conexión a internet y permisos."
        fi
    else
        log_info "Powerlevel10k ya parece clonado."
    fi

    # Copiar archivos de configuración local del usuario
    log_info "Copiando archivos de configuración local (.zshrc, .p10k.zsh) para el usuario '$TARGET_USER'..."
    if [ -f "$USER_CONFIG_DIR/.zshrc" ]; then
        log_info "Copiando .zshrc..."
        # Hacer copia de seguridad del .zshrc existente si no es un enlace simbólico
        if [ -f "$TARGET_USER_HOME/.zshrc" ] && [ ! -L "$TARGET_USER_HOME/.zshrc" ]; then
            if sudo mv "$TARGET_USER_HOME/.zshrc" "$TARGET_USER_HOME/.zshrc.bak_$(date +%Y%m%d_%H%M%S)"; then
                 log_info "Copia de seguridad de .zshrc existente creada."
            else
                 log_warn "Fallo al crear copia de seguridad de .zshrc."
            fi
        fi
        # Copiar y asegurar propietario/grupo correcto
        if sudo cp "$USER_CONFIG_DIR/.zshrc" "$TARGET_USER_HOME/.zshrc"; then
            sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_USER_HOME/.zshrc" || log_warn "Fallo al cambiar propietario/grupo de .zshrc."
            log_info ".zshrc local copiado."
        else
            log_warn "Fallo al copiar .zshrc local."
        fi
    else
        log_warn "No se encontró el archivo .zshrc local en $USER_CONFIG_DIR/.zshrc. Saltando copia."
    fi

     if [ -f "$USER_CONFIG_DIR/.p10k.zsh" ]; then
        log_info "Copiando .p10k.zsh..."
         # Hacer copia de seguridad del .p10k.zsh existente si no es un enlace simbólico
        if [ -f "$TARGET_USER_HOME/.p10k.zsh" ] && [ ! -L "$TARGET_USER_HOME/.p10k.zsh" ]; then
            if sudo mv "$TARGET_USER_HOME/.p10k.zsh" "$TARGET_USER_HOME/.p10k.zsh.bak_$(date +%Y%m%d_%H%M%S)"; then
                log_info "Copia de seguridad de .p10k.zsh existente creada."
            else
                 log_warn "Fallo al crear copia de seguridad de .p10k.zsh."
            fi
        fi
        # Copiar y asegurar propietario/grupo correcto
        if sudo cp "$USER_CONFIG_DIR/.p10k.zsh" "$TARGET_USER_HOME/.p10k.zsh"; then
            sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_USER_HOME/.p10k.zsh" || log_warn "Fallo al cambiar propietario/grupo de .p10k.zsh."
            log_info ".p10k.zsh local copiado."
        else
            log_warn "Fallo al copiar .p10k.zsh local."
        fi
    else
        log_warn "No se encontró el archivo .p10k.zsh local en $USER_CONFIG_DIR/.p10k.zsh. Powerlevel10k usará su asistente interactivo la primera vez."
    fi

    log_info "Configuración de terminal completada (requiere que cambies tu shell y reinicies/re-loguees)."


    log_info "Instalando aplicaciones Flatpak (Flathub y Fedora) para el usuario '$TARGET_USER'..."
    # Usar 'sudo -u' para ejecutar flatpak como el usuario normal con la opción -H
    # flatpak install --user corre solo para el usuario que ejecuta el comando, no afecta a otros.
    log_info "Instalando Flatpaks de Flathub..."
    if ! sudo -H -u "$TARGET_USER" flatpak install --user -y flathub \
        org.audacityteam.Audacity \
        cc.arduino.IDE2 \
        com.bitwarden.desktop \
        com.microsoft.Edge \
        com.obsproject.Studio \
        com.spotify.Client \
        org.onlyoffice.desktopeditors \
        org.freedesktop.Platform \
        org.gnome.Platform \
        org.kde.Platform \
        org.freedesktop.Platform.GL.default \
        org.freedesktop.Platform.VAAPI.Intel \
        org.freedesktop.Platform.openh264; then
        log_warn "Falló la instalación de una o más aplicaciones Flatpak de Flathub."
    fi


    log_info "Instalando Flatpaks de Fedora remote..."
     if ! sudo -H -u "$TARGET_USER" flatpak install --user -y fedora \
        org.eclipse.Java \
        com.github.tchx84.Flatseal \
        org.fedoraproject.Platform \
        org.gtk.Gtk3theme.Breeze; then
        log_warn "Falló la instalación de una o más aplicaciones Flatpak de Fedora."
     fi

    # Instalar AppImage manager (Gearlever) vía Flatpak
    log_info "Instalando Gearlever (AppImage Manager) vía Flatpak para el usuario '$TARGET_USER'..."
    if ! sudo -H -u "$TARGET_USER" flatpak install --user -y flathub it.mijorus.gearlever; then
         log_warn "Falló la instalación de Gearlever (Flatpak)."
    fi
    log_info "Aplicaciones Flatpak instaladas."


    log_info "Instalando aplicaciones Snap..."
    # Asegurarse de que snapd está activo antes de instalar snaps
    if ! systemctl is-active --quiet snapd; then
         log_error "El servicio snapd no está activo. No se pueden instalar aplicaciones Snap."
         log_warn "Intenta iniciar snapd manualmente con 'sudo systemctl start snapd' y ejecuta esta fase de nuevo."
    else
        log_info "Instalando snaps..."
        # snap install ... || log_warn "Fallo al instalar snap." # Set -e no funciona bien con snap install
        snap install android-studio --classic || log_warn "Falló la instalación de Android Studio (snap)."
        snap install core22 || log_warn "Falló la instalación de core22 (snap base)."
        log_info "Aplicaciones Snap instaladas (si snapd está activo y las instalaciones tuvieron éxito)."
    fi


    log_info "=== Fin de la Fase 3 ==="
    log_warn "La configuración de terminal y la instalación de aplicaciones han finalizado."
    log_warn "Ahora puedes ejecutar la configuración opcional de Secure Boot si lo deseas."
    log_warn "Ejecuta este script con el argumento 'phase4':"
    log_warn "sudo ./setup.sh phase4"
    log_warn "Recuerda ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_YELLOW} para que todos los cambios (grupos, PATH, Zsh, apps) surtan efecto."
    exit 0
}

phase4_secure_boot() {
    log_info "=== Fase 4: Configuración Opcional de Secure Boot ==="
    log_warn "${COLOR_RED}¡ATENCIÓN! Esta fase requiere INTERACCIÓN MANUAL después del próximo reinicio.${COLOR_RESET}"
    log_warn "${COLOR_RED}Lee cuidadosamente las instrucciones que se mostrarán.${COLOR_RESET}"

    check_root # Asegurarse de que se ejecuta con root.

    # 10. Validación de acción peligrosa: Configuración de Secure Boot
    log_warn "La siguiente acción preparará tu sistema para Secure Boot."
    log_warn "Esto generará una clave MOK y la importará en el firmware UEFI."
    read -r -p "¿Desea proceder con la configuración de Secure Boot? [S/n]: " confirm_secureboot
    confirm_secureboot=${confirm_secureboot:-S}

    if [[ "$confirm_secureboot" =~ ^[Ss]$ ]]; then
        log_info "Instalando herramientas de Secure Boot..."
        # dnf install -y kmodtool akmods mokutil openssl || log_error "Fallo al instalar herramientas de Secure Boot." # Set -e
        dnf install -y kmodtool akmods mokutil openssl

        log_info "Generando clave MOK para firmar módulos del kernel..."
        # La clave se genera por defecto en /etc/pki/akmods.
        # kmodgenca -a || log_error "Fallo al generar la clave MOK. Abortando Secure Boot setup." # Set -e
        kmodgenca -a

        log_info "Importando la clave pública (.der) en la lista de claves MOK..."
        log_warn "${COLOR_RED}Se te pedirá que ingreses una CONTRASEÑA para enrollar la clave. ¡Anótala! La necesitarás después de reiniciar.${COLOR_RESET}"
        # mokutil --import /etc/pki/akmods/certs/public_key.der || log_error "Error al importar la clave MOK. Abortando Secure Boot setup." # Set -e
        # Ejecutar interactivo para la contraseña
        if mokutil --import /etc/pki/akmods/certs/public_key.der; then
             log_info "Comando de importación de clave MOK ejecutado con éxito."
        else
             log_error "Fallo al ejecutar el comando 'mokutil --import'. Verifica si Secure Boot está habilitado en BIOS/UEFI y si tienes permisos."
             exit 1 # Salir explícitamente en caso de fallo crítico
        fi

        # 11. Instrucciones CRÍTICAS para el usuario (mejoradas para claridad)
        log_warn "${COLOR_RED}=== PASOS MANUALES REQUERIDOS DESPUÉS DEL REINICIO ===${COLOR_RESET}"
        log_warn "La importación de la clave NO está completa todavía."
        log_warn "Debes INTERACTUAR MANUALMENTE con la pantalla de MOK Management al reiniciar."
        log_warn "${COLOR_YELLOW}1. ${COLOR_RESET} Reinicia tu sistema ahora: ${COLOR_GREEN}sudo systemctl reboot${COLOR_RESET}"
        log_warn "${COLOR_YELLOW}2. ${COLOR_RESET} Justo antes de que Fedora inicie, verás una pantalla (a menudo azul/negra) de ${COLOR_RED}'MOK Management'${COLOR_RESET} o similar (puede variar según tu firmware UEFI)."
        log_warn "${COLOR_YELLOW}3. ${COLOR_RESET} Selecciona ${COLOR_GREEN}'Enroll MOK'${COLOR_RESET} (o similar)."
        log_warn "${COLOR_YELLOW}4. ${COLOR_RESET} Sigue las indicaciones, selecciona ${COLOR_GREEN}'Continue'${COLOR_RESET} o confirma."
        log_warn "${COLOR_YELLOW}5. ${COLOR_RESET} Se te pedirá la ${COLOR_RED}CONTRASEÑA${COLOR_RESET} que introdujiste cuando ejecutaste el comando 'mokutil --import' anteriormente."
        log_warn "${COLOR_RED}¡ADVERTENCIA: La distribución del teclado en esta pantalla a menudo es QWERTY!${COLOR_RESET}"
        log_warn "${COLOR_YELLOW}6. ${COLOR_RESET} Después de ingresar la contraseña correctamente, confirma la inscripción."
        log_warn "${COLOR_YELLOW}7. ${COLOR_RESET} El sistema te pedirá que reinicies de nuevo. Hazlo."
        log_info "Una vez que hayas completado estos pasos manuales, tu clave personalizada estará inscrita y los módulos del kernel firmados localmente (como los drivers Nvidia instalados con akmod) funcionarán con Secure Boot habilitado."

        log_info "=== Fin de la Fase 4 ==="
        log_warn "Ahora debes ${COLOR_RED}REINICIAR${COLOR_YELLOW} para completar el proceso de Secure Boot manualmente."
        log_warn "Después del reinicio y la interacción con MOK Management, tu setup estará casi completo."
        # No salimos automáticamente aquí, ya que el usuario necesita leer las instrucciones cruciales.
        # Sugerimos el comando de reinicio, pero el usuario debe ejecutarlo.
    else
        log_info "Configuración de Secure Boot cancelada por el usuario."
        log_info "=== Fin de la Fase 4 ==="
    fi

    # No hay exit 0 aquí, ya que la fase instruye al usuario a reiniciar manualmente.
}


# --- Lógica principal del script ---

# Ejecutar validaciones iniciales antes de cualquier fase
check_dependencies
check_config_files

# Procesar el argumento de la línea de comandos
case "${1:-}" in # Usamos ${1:-} para manejar el caso sin argumentos
    phase1)
        phase1_initial_setup
        ;;
    phase2)
        phase2_system_dev_base
        ;;
    phase3)
        phase3_terminal_apps
        ;;
    phase4)
        phase4_secure_boot
        ;;
    all)
        log_warn "Has solicitado ver la secuencia de ejecución completa."
        log_warn "Nota: Este modo NO ejecuta todas las fases automáticamente de principio a fin."
        log_warn "Debe ejecutar cada fase por separado con 'sudo ./setup.sh <fase>' y realizar los reinicios/re-logueos cuando se le indique."
        log_info "${COLOR_GREEN}Secuencia de ejecución recomendada:${COLOR_RESET}"
        log_info "1. ${COLOR_YELLOW}sudo ./setup.sh phase1${COLOR_RESET} (Configuración inicial, repos, herramientas básicas, firmware)"
        log_warn "   -> ${COLOR_RED}¡IMPORTANTE! REINICIAR antes de pasar a la fase 2.${COLOR_RESET}"
        log_info "2. ${COLOR_YELLOW}sudo ./setup.sh phase2${COLOR_RESET} (Base sistema, drivers, multimedia, entornos de desarrollo)"
        log_warn "   -> ${COLOR_RED}¡IMPORTANTE! Cerrar/Iniciar sesión (o REINICIAR) antes de pasar a la fase 3 para aplicar cambios de grupo/PATH.${COLOR_RESET}"
        log_info "3. ${COLOR_YELLOW}sudo ./setup.sh phase3${COLOR_RESET} (Configuración de Terminal, Apps Flatpak/Snap/AppImage)"
        log_warn "   -> ${COLOR_RED}¡IMPORTANTE! Cerrar/Iniciar sesión (o REINICIAR) para que la nueva shell y las aplicaciones estén disponibles.${COLOR_RESET}"
        log_info "4. ${COLOR_YELLOW}sudo ./setup.sh phase4${COLOR_RESET} (Configuración OPCIONAL de Secure Boot para módulos firmados localmente)"
        log_warn "   -> ${COLOR_RED}¡IMPORTANTE! REINICIAR INMEDIATAMENTE y completar los pasos manuales en MOK Management.${COLOR_RESET}"
        log_info "Consulta el archivo de log en $LOGFILE para detalles de la ejecución."
        ;;
    *)
        log_error "Uso: sudo ./setup.sh <fase>"
        log_warn "${COLOR_YELLOW}Fases disponibles:${COLOR_RESET}"
        log_warn "  ${COLOR_GREEN}phase1${COLOR_RESET}: Configuración inicial, repositorios, herramientas básicas, firmware. ${COLOR_RED}Requiere REINICIO al finalizar.${COLOR_RESET}"
        log_warn "  ${COLOR_GREEN}phase2${COLOR_RESET}: Soporte del sistema (drivers, multimedia), entornos de desarrollo (virtualización, docker, lenguajes). ${COLOR_RED}Requiere cerrar/iniciar sesión (o REINICIAR) al finalizar.${COLOR_RESET}"
        log_warn "  ${COLOR_GREEN}phase3${COLOR_RESET}: Configuración de terminal (Zsh, P10k), instalación de aplicaciones (Flatpak, Snap, AppImage). ${COLOR_RED}Requiere cerrar/iniciar sesión (o REINICIAR) para ver cambios.${COLOR_RESET}"
        log_warn "  ${COLOR_GREEN}phase4${COLOR_RESET}: Configuración OPCIONAL de Secure Boot. ${COLOR_RED}Requiere REINICIAR y pasos manuales en MOK Management al finalizar.${COLOR_RESET}"
        log_warn ""
        log_warn "${COLOR_YELLOW}Para ver la secuencia completa y las instrucciones detalladas, usa:${COLOR_RESET} ${COLOR_GREEN}./setup.sh all${COLOR_RESET}"
        exit 1
        ;;
esac

# Mensaje final si el script no salió por un error o un exit explícito en una fase.
# Esto solo debería ocurrir si la fase 4 se ejecutó sin errores o si se usó el argumento 'all'.
log_info "Script de setup finalizado. Consulta el archivo de log en $LOGFILE para más detalles."
log_info "¡Recuerda los pasos de ${COLOR_RED}REINICIO o CIERRE/INICIO DE SESIÓN${COLOR_RESET} si aplicaste fases 1, 2 o 3!"

# --- Notas Adicionales ---
# - Considera usar 'dialog' o 'whiptail' para menús y prompts más amigables.
# - Revisa el manejo de defaultyes=True en dnf.conf, puede ser arriesgado.
# - Para una instalación más segura de Bun, descarga el script, revísalo y ejecútalo localmente.
# - Implementa la adición de la clave GPG para el repositorio Terra en lugar de --nogpgcheck.
# - Considera usar ShellCheck (shellcheck.net) para analizar el script y encontrar posibles errores o malas prácticas.
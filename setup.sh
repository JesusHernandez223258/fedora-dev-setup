#!/bin/bash

# ==============================================================================
# PRE-CHECKS AND SCRIPT INITIALIZATION
    # ==============================================================================

# --- Root Privileges and Dialog Utility Check ---
core_check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo "🛑 Este script debe ejecutarse como root o con sudo."
        exit 1
    fi
}

core_check_dialog_utility() {
    if ! command -v whiptail > /dev/null && ! command -v dialog > /dev/null; then
        echo "⚠️ whiptail o dialog no están instalados. Por favor, instálalos para usar este script."
        echo "Puedes instalar whiptail con: sudo dnf install -y newt"
        exit 1
    fi
    DIALOG_CMD="whiptail"
    if ! command -v whiptail > /dev/null; then
        DIALOG_CMD="dialog"
    fi
}

# --- Global Variables and Logging Setup ---
LOG_FILE="/var/log/fedora_postinstall_$(date +%Y%m%d-%H%M%S).log"
touch "$LOG_FILE"
# Attempt to change owner, ignore error if SUDO_USER is not set (e.g., direct root execution)
chown "$SUDO_USER":"$SUDO_USER" "$LOG_FILE" 2>/dev/null
chmod 644 "$LOG_FILE"

echo "=== Inicio del Script de Post-Instalación Fedora $(date) ===" | tee -a "$LOG_FILE"
echo "Ejecutado por: $(whoami)" | tee -a "$LOG_FILE"
echo "Log detallado de operaciones: $LOG_FILE"

# ==============================================================================
# CORE UTILITY FUNCTIONS
# ==============================================================================

util_log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

util_run_command() {
    local title_msg="$1"
    local command_to_run="$2"
    local success_msg="$3"
    local failure_msg="$4"

    $DIALOG_CMD --title "Procesando" --infobox "$title_msg\n\nEsto puede tardar unos momentos...\nRevisa $LOG_FILE para detalles." 10 70

    util_log_message "Ejecutando: $title_msg"
    util_log_message "Comando: $command_to_run"

    if bash -c "$command_to_run" >> "$LOG_FILE" 2>&1; then
        util_log_message "Éxito: $title_msg"
        $DIALOG_CMD --title "Éxito" --msgbox "$success_msg" 10 70
        return 0
    else
        util_log_message "ERROR: $title_msg. Código de salida: $?"
        local error_details
        error_details=$(tail -n 10 "$LOG_FILE")
        $DIALOG_CMD --title "Error" --msgbox "$failure_msg\n\nError Code: $?\nÚltimas líneas del log:\n$error_details\n\nConsulta $LOG_FILE para el log completo." 20 78
        return 1
    fi
}

core_check_internet_connection() {
    util_log_message "Verificando conexión a Internet..."
    if ! nmcli networking connectivity | grep -q "full" && ! curl -s --head https://fedoraproject.org | grep -q "200 OK"; then
        util_log_message "Error de conexión a Internet."
        $DIALOG_CMD --title "Error de Conexión" --msgbox "🛑 No se detectó una conexión a Internet funcional.\n\nAlgunas operaciones pueden fallar o el script no puede continuar.\nPor favor, verifica tu conexión e inténtalo de nuevo." 12 78
        exit 1
    fi
    util_log_message "Conexión a Internet verificada."
    $DIALOG_CMD --title "Conexión Verificada" --infobox "✅ Conexión a Internet verificada." 5 60
    sleep 1
}

# ==============================================================================
# SYSTEM CONFIGURATION FUNCTIONS
# ==============================================================================

system_configure_dnf() {
    util_log_message "Iniciando configuración personalizada de DNF."
    if ($DIALOG_CMD --title "DNF Personalizado" --yesno "¿Aplicar configuración personalizada de DNF (max_parallel_downloads=10, deltarpm=True, defaultyes=True)?" 10 78); then
        util_log_message "Usuario aceptó aplicar configuración DNF personalizada."
        $DIALOG_CMD --title "Procesando" --infobox "Aplicando configuración personalizada de DNF..." 8 60

        util_log_message "Escribiendo configuración en /etc/dnf/dnf.conf"
        cat <<EOF_DNF | sudo tee /etc/dnf/dnf.conf > /dev/null
# see \`man dnf.conf\` for defaults and possible options

[main]
max_parallel_downloads=10
deltarpm=True
defaultyes=True
EOF_DNF
        if [ $? -eq 0 ]; then
            util_log_message "Éxito: Configuración DNF personalizada aplicada."
            $DIALOG_CMD --title "Éxito" --msgbox "✅ Configuración personalizada de DNF aplicada." 10 70
        else
            util_log_message "ERROR: Aplicando configuración DNF personalizada."
            $DIALOG_CMD --title "Error" --msgbox "⚠️ Error aplicando configuración personalizada de DNF. Consulta $LOG_FILE." 10 70
        fi
    else
        util_log_message "Configuración DNF personalizada omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Configuración personalizada de DNF omitida." 8 60
    fi
}

system_configure_repositories() {
    util_log_message "Iniciando activación de repositorios adicionales."
    REPO_CHOICES=$($DIALOG_CMD --title "Activar Repositorios Adicionales" --checklist \
        "Selecciona los repositorios a configurar/activar:" 15 78 5 \
        "RPMFUSION" "RPM Fusion (Free y Nonfree)" ON \
        "TERRA" "Repositorio Terra (opcional)" OFF \
        "FLATHUB" "Flathub para Flatpak" ON \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -eq 0 ]; then
        util_log_message "Repositorios seleccionados: $REPO_CHOICES"
        if [[ "$REPO_CHOICES" == *"RPMFUSION"* ]]; then
            util_run_command "Configurando RPM Fusion" \
                "sudo dnf install -y \
                  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm \
                  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm" \
                "✅ Repositorios RPM Fusion configurados." \
                "⚠️ Error configurando RPM Fusion."
        else
            util_log_message "RPM Fusion omitido por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ RPM Fusion omitido." 8 60
        fi

        if [[ "$REPO_CHOICES" == *"TERRA"* ]]; then
            util_run_command "Agregando Repositorio Terra" \
                "sudo dnf install --nogpgcheck \
                  --repofrompath 'terra,https://repos.fyralabs.com/terra\$releasever' terra-release -y" \
                "✅ Repositorio Terra agregado." \
                "⚠️ Error agregando Repositorio Terra."
        else
            util_log_message "Repositorio Terra omitido por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ Repositorio Terra omitido." 8 60
        fi

        if [[ "$REPO_CHOICES" == *"FLATHUB"* ]]; then
            util_run_command "Configurando Flathub" \
                "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" \
                "✅ Repositorio Flathub para Flatpak configurado." \
                "⚠️ Error configurando Flathub."
        else
            util_log_message "Flathub omitido por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ Flathub omitido." 8 60
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Configuración de repositorios adicionales completada según selección." 8 70
    else
        util_log_message "Configuración de repositorios adicionales cancelada por el usuario."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Configuración de repositorios adicionales cancelada." 8 60
    fi
}

system_perform_initial_update() {
    util_log_message "Iniciando actualización inicial del sistema."
    if ($DIALOG_CMD --title "Actualización Inicial" --yesno "¿Realizar actualización inicial completa del sistema AHORA?\n(Esto tomará tiempo y REQUERIRÁ REINICIO)" 10 78); then
        util_log_message "Usuario aceptó realizar actualización inicial."
        util_run_command "Actualizando grupo 'core'" \
            "sudo dnf group upgrade -y core" \
            "✅ Grupo 'core' actualizado." \
            "⚠️ Error actualizando grupo 'core'." || return 1

        util_run_command "Realizando actualización completa del sistema" \
            "sudo dnf update -y && sudo dnf upgrade -y --refresh" \
            "✅ Actualización completa del sistema realizada." \
            "⚠️ Error en 'dnf update/upgrade'." || return 1

        util_log_message "Actualización inicial completada. Requiere reinicio."
        $DIALOG_CMD --title "Reinicio Requerido" --msgbox "El sistema necesita reiniciarse para aplicar todas las actualizaciones.\nEl script terminará ahora. Por favor, reinicia manualmente." 10 60
        exit 0
    else
        util_log_message "Actualización inicial del sistema omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Actualización inicial del sistema omitida." 8 60
    fi
}

system_update_firmware_lvfs() {
    util_log_message "Iniciando actualización de firmware LVFS."
    if ($DIALOG_CMD --title "Firmware LVFS" --yesno "¿Buscar y aplicar actualizaciones de firmware (LVFS)?" 10 70); then
        util_log_message "Usuario aceptó buscar actualizaciones de firmware."
        util_run_command "Refrescando metadatos de firmware (fwupdmgr)" \
            "sudo fwupdmgr refresh --force" \
            "✅ Metadatos de firmware refrescados." \
            "⚠️ Error en 'fwupdmgr refresh --force'."

        util_run_command "Obteniendo dispositivos (fwupdmgr)" \
            "sudo fwupdmgr get-devices" \
            "✅ Dispositivos listados." \
            "⚠️ Error en 'fwupdmgr get-devices'."

        util_run_command "Buscando actualizaciones de firmware (fwupdmgr)" \
            "sudo fwupdmgr get-updates" \
            "✅ Búsqueda de actualizaciones de firmware completada." \
            "⚠️ Error en 'fwupdmgr get-updates'."

        if ($DIALOG_CMD --title "Aplicar Actualización de Firmware" --yesno "¿Proceder con la instalación de las actualizaciones de firmware detectadas (si existen)?" 10 70); then
            util_log_message "Usuario aceptó instalar actualizaciones de firmware."
            util_run_command "Instalando actualizaciones de firmware (fwupdmgr)" \
                "sudo fwupdmgr update -y" \
                "✅ Actualizaciones de firmware instaladas (si las hubo)." \
                "⚠️ Error en 'fwupdmgr update'."
        else
            util_log_message "Instalación de actualizaciones de firmware omitida por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ Instalación de actualizaciones de firmware omitida por el usuario." 8 70
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Proceso de firmware LVFS completado." 8 60
    else
        util_log_message "Actualización de firmware LVFS omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Actualización de firmware LVFS omitida." 8 60
    fi
}

# ==============================================================================
# MULTIMEDIA AND GRAPHICS CONFIGURATION
# ==============================================================================

media_install_codecs() {
    util_log_message "Iniciando instalación de códecs multimedia."
    if ($DIALOG_CMD --title "Códecs Multimedia" --yesno "¿Instalar códecs multimedia completos y paquetes de reproducción?" 10 78); then
        util_log_message "Usuario aceptó instalar códecs multimedia."
        util_run_command "Instalando grupos 'multimedia' y 'sound-and-video'" \
            "sudo dnf group install -y multimedia sound-and-video" \
            "✅ Grupos 'multimedia' y 'sound-and-video' instalados." \
            "⚠️ Error instalando grupos multimedia." || return 1

        util_run_command "Cambiando ffmpeg-free por ffmpeg" \
            "sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing" \
            "✅ ffmpeg-free cambiado por ffmpeg." \
            "⚠️ Error en swap ffmpeg-free por ffmpeg." || return 1

        util_run_command "Instalando ffmpeg-libs y libva" \
            "sudo dnf install -y ffmpeg-libs libva libva-utils" \
            "✅ ffmpeg-libs y libva instalados." \
            "⚠️ Error instalando ffmpeg-libs, libva." || return 1

        $DIALOG_CMD --title "Completado" --msgbox "✅ Códecs y paquetes de reproducción listos." 8 60
    else
        util_log_message "Instalación de códecs multimedia omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Instalación de códecs multimedia omitida." 8 60
    fi
}

media_configure_graphics_drivers() {
    util_log_message "Iniciando selección de drivers gráficos."
    CHOICE=$($DIALOG_CMD --title "Drivers Gráficos y Aceleración" --menu "Selecciona tu hardware gráfico principal y opciones de aceleración:" 20 78 15 \
        "1" "Intel (Instalar driver base y aceleración)" \
        "2" "NVIDIA (Instalar driver propietario y aceleración)" \
        "3" "AMD (Configurar aceleración de video)" \
        "4" "Intel + NVIDIA (Híbrido - Instalar ambos drivers base)" \
        "5" "Solo instalar driver Intel base (xorg-x11-drv-intel)" \
        "6" "Solo instalar driver NVIDIA base (akmod-nvidia)" \
        "7" "Volver al menú principal" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
        util_log_message "Selección de drivers cancelada."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Selección de drivers cancelada." 8 60
        return
    fi
    util_log_message "Opción de drivers seleccionada: $CHOICE"

    case $CHOICE in
        1) # Intel Completo
            util_run_command "Instalando driver Intel base" \
                "sudo dnf install -y xorg-x11-drv-intel" \
                "✅ Driver Intel base (xorg-x11-drv-intel) instalado." \
                "⚠️ Error instalando driver Intel base." || return 1

            INTEL_GEN_CHOICE=$($DIALOG_CMD --title "Aceleración Intel" --radiolist "Selecciona la generación de tu GPU Intel para VA-API:" 15 70 5 \
                "new" "Nuevas generaciones (Gen9+): intel-media-driver" ON \
                "old" "Viejas generaciones (pre-Gen9): libva-intel-driver" OFF \
                "both" "Ambas (si no estás seguro)" OFF 3>&1 1>&2 2>&3)
            intel_gen_status=$?
            if [ $intel_gen_status -eq 0 ]; then
                util_log_message "Selección de aceleración Intel: $INTEL_GEN_CHOICE"
                case $INTEL_GEN_CHOICE in
                    new)  util_run_command "Instalando intel-media-driver" "sudo dnf install -y intel-media-driver" "✅ intel-media-driver instalado." "⚠️ Error instalando intel-media-driver.";;
                    old)  util_run_command "Instalando libva-intel-driver" "sudo dnf install -y libva-intel-driver" "✅ libva-intel-driver instalado." "⚠️ Error instalando libva-intel-driver.";;
                    both) util_run_command "Instalando intel-media-driver y libva-intel-driver" "sudo dnf install -y intel-media-driver libva-intel-driver" "✅ intel-media-driver y libva-intel-driver instalados." "⚠️ Error instalando ambos drivers VAAPI.";;
                esac
            else
                 util_log_message "Selección de aceleración Intel cancelada."
                $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Selección de aceleración Intel cancelada. Driver base instalado." 10 70
            fi
            ;;
        2) # NVIDIA Completo
            NVIDIA_COMPONENTS_CHOICES=$($DIALOG_CMD --title "Componentes NVIDIA" --checklist \
                "Selecciona los componentes NVIDIA a instalar:" 15 78 5 \
                "AKMOD" "Driver principal (akmod-nvidia)" ON \
                "VAAPI" "Soporte VAAPI (libva-nvidia-driver)" ON \
                "CUDA" "Soporte CUDA (xorg-x11-drv-nvidia-cuda)" OFF \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                util_log_message "Componentes NVIDIA seleccionados: $NVIDIA_COMPONENTS_CHOICES"
                if [[ "$NVIDIA_COMPONENTS_CHOICES" == *"AKMOD"* ]]; then
                    util_run_command "Instalando akmod-nvidia" "sudo dnf install -y akmod-nvidia" "✅ akmod-nvidia instalado." "⚠️ Error instalando akmod-nvidia."
                fi
                if [[ "$NVIDIA_COMPONENTS_CHOICES" == *"VAAPI"* ]]; then
                    util_run_command "Instalando libva-nvidia-driver" "sudo dnf install -y libva-nvidia-driver.i686 libva-nvidia-driver.x86_64" "✅ libva-nvidia-driver (VAAPI) instalado." "⚠️ Error instalando libva-nvidia-driver."
                fi
                if [[ "$NVIDIA_COMPONENTS_CHOICES" == *"CUDA"* ]]; then
                    util_run_command "Instalando xorg-x11-drv-nvidia-cuda" "sudo dnf install -y xorg-x11-drv-nvidia-cuda" "✅ xorg-x11-drv-nvidia-cuda instalado." "⚠️ Error instalando xorg-x11-drv-nvidia-cuda."
                fi
                $DIALOG_CMD --title "Completado" --msgbox "✅ Componentes NVIDIA configurados según selección." 8 70
            else
                util_log_message "Selección de componentes NVIDIA cancelada."
                $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Selección de componentes NVIDIA cancelada." 8 60
            fi
            ;;
        3) # AMD Aceleración
            AMD_COMPONENTS_CHOICES=$($DIALOG_CMD --title "Componentes Aceleración AMD" --checklist \
                "Selecciona los componentes de aceleración para AMD:" 15 78 5 \
                "MESA_FW" "Drivers Freeworld (mesa-va/vdpau-drivers-freeworld)" ON \
                "32BIT" "Compatibilidad 32-bit (para Steam, etc.)" ON \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                util_log_message "Componentes AMD seleccionados: $AMD_COMPONENTS_CHOICES"
                if [[ "$AMD_COMPONENTS_CHOICES" == *"MESA_FW"* ]]; then
                    util_run_command "Instalando drivers Freeworld para AMD (64-bit)" \
                        "sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld && sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld" \
                        "✅ Drivers Freeworld para AMD (64-bit) instalados." \
                        "⚠️ Error instalando drivers Freeworld para AMD (64-bit)."
                fi
                if [[ "$AMD_COMPONENTS_CHOICES" == *"32BIT"* ]]; then
                    if [[ "$AMD_COMPONENTS_CHOICES" != *"MESA_FW"* ]]; then
                         util_run_command "Instalando drivers Freeworld para AMD (64-bit, dependencia de 32-bit)" \
                            "sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld && sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld" \
                            "✅ Drivers Freeworld para AMD (64-bit) instalados." \
                            "⚠️ Error instalando drivers Freeworld para AMD (64-bit)."
                    fi
                    util_run_command "Instalando drivers Freeworld para AMD (32-bit)" \
                        "sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 && sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686" \
                        "✅ Drivers Freeworld para AMD (32-bit) instalados." \
                        "⚠️ Error instalando drivers Freeworld para AMD (32-bit)."
                fi
                 $DIALOG_CMD --title "Completado" --msgbox "✅ Aceleración de video AMD configurada según selección." 8 70
            else
                util_log_message "Selección de componentes AMD cancelada."
                $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Selección de componentes AMD cancelada." 8 60
            fi
            ;;
        4) # Intel + NVIDIA Híbrido
            util_run_command "Instalando driver Intel base" "sudo dnf install -y xorg-x11-drv-intel" "✅ Driver Intel base instalado." "⚠️ Error instalando driver Intel base."
            util_run_command "Instalando driver NVIDIA base" "sudo dnf install -y akmod-nvidia" "✅ Driver NVIDIA base instalado." "⚠️ Error instalando driver NVIDIA base."
            $DIALOG_CMD --msgbox "Drivers base Intel y NVIDIA instalados.\n\nConsidera ejecutar las opciones específicas de Intel/NVIDIA en este menú para configurar la aceleración y componentes adicionales como CUDA o intel-media-driver si es necesario." 12 78
            ;;
        5) # Solo Intel Base
            util_run_command "Instalando driver Intel base" "sudo dnf install -y xorg-x11-drv-intel" "✅ Driver Intel base instalado." "⚠️ Error instalando driver Intel base."
            ;;
        6) # Solo NVIDIA Base
            util_run_command "Instalando driver NVIDIA base" "sudo dnf install -y akmod-nvidia" "✅ Driver NVIDIA base instalado." "⚠️ Error instalando driver NVIDIA base."
            ;;
        7) return ;;
        *)  util_log_message "Opción inválida en drivers: $CHOICE"
            $DIALOG_CMD --title "Error" --msgbox "❌ Opción inválida." 6 30 ;;
    esac
}

media_install_h264_support() {
    util_log_message "Iniciando instalación de soporte H.264."
    if ($DIALOG_CMD --title "Soporte H.264" --yesno "¿Instalar soporte H.264 (OpenH264 para Firefox y GStreamer)?" 10 70); then
        util_log_message "Usuario aceptó instalar soporte H.264."
        util_run_command "Instalando paquetes OpenH264" \
            "sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264" \
            "✅ Paquetes OpenH264 instalados." \
            "⚠️ Error instalando paquetes OpenH264." || return 1

        util_run_command "Habilitando repositorio fedora-cisco-openh264" \
            "sudo dnf config-manager --set-enabled fedora-cisco-openh264" \
            "✅ Repositorio fedora-cisco-openh264 habilitado." \
            "⚠️ Error habilitando repositorio fedora-cisco-openh264." || return 1

        $DIALOG_CMD --title "Acción Manual Requerida" --msgbox "✅ Soporte H.264 instalado.\n\nPara Firefox, abre 'about:addons', ve a Plugins, busca 'OpenH264 Video Codec provided by Cisco Systems, Inc.' y asegúrate de que esté activado ('Activar siempre' o 'Preguntar para activar')." 15 78
    else
        util_log_message "Instalación de soporte H.264 omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Instalación de soporte H.264 omitida." 8 60
    fi
}

media_install_dvd_and_tainted_firmware() {
    util_log_message "Iniciando instalación de soporte DVD y firmware desde repositorios Tainted."
    DVD_FIRMWARE_CHOICES=$($DIALOG_CMD --title "Soporte DVD y Firmware Adicional (Tainted)" --checklist \
        "Selecciona los componentes a instalar:" 15 78 5 \
        "TAINTED_REPOS" "Habilitar repos RPM Fusion Tainted (necesario para lo siguiente)" ON \
        "LIBDVDCSS" "Soporte para reproducción de DVDs (libdvdcss)" ON \
        "EXTRA_FIRMWARE" "Firmwares adicionales propietarios (desde Tainted)" OFF \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -eq 0 ]; then
        util_log_message "Opciones DVD/Firmware Tainted seleccionadas: $DVD_FIRMWARE_CHOICES"
        if [[ "$DVD_FIRMWARE_CHOICES" == *"TAINTED_REPOS"* ]] || \
           [[ "$DVD_FIRMWARE_CHOICES" == *"LIBDVDCSS"* ]] || \
           [[ "$DVD_FIRMWARE_CHOICES" == *"EXTRA_FIRMWARE"* ]]; then
            util_run_command "Habilitando repositorios RPM Fusion Tainted" \
                "sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted" \
                "✅ Repositorios Tainted de RPM Fusion habilitados." \
                "⚠️ Error habilitando repositorios Tainted."
        fi

        if [[ "$DVD_FIRMWARE_CHOICES" == *"LIBDVDCSS"* ]]; then
            util_run_command "Instalando libdvdcss" \
                "sudo dnf install -y libdvdcss" \
                "✅ Soporte para reproducción de DVDs (libdvdcss) instalado." \
                "⚠️ Error instalando libdvdcss."
        else
            util_log_message "libdvdcss omitido por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ libdvdcss omitido." 8 60
        fi

        if [[ "$DVD_FIRMWARE_CHOICES" == *"EXTRA_FIRMWARE"* ]]; then
            util_run_command "Instalando firmwares adicionales desde Tainted" \
                "sudo dnf --repo=rpmfusion-nonfree-tainted install -y \"*-firmware\"" \
                "✅ Firmwares adicionales instalados." \
                "⚠️ Error instalando firmwares adicionales."
        else
            util_log_message "Firmwares adicionales (Tainted) omitidos por el usuario."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ Firmwares adicionales (Tainted) omitidos." 8 60
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Configuración de DVDs y firmwares (Tainted) completada según selección." 8 70
    else
        util_log_message "Configuración de soporte DVD y firmware (Tainted) cancelada."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Configuración de soporte DVD y firmware (Tainted) cancelada." 8 60
    fi
}

# ==============================================================================
# FILESYSTEM AND STORAGE FUNCTIONS
# ==============================================================================

storage_optimize_btrfs() {
    util_log_message "Iniciando optimización BTRFS."
    if ! mount | grep -q 'on / type btrfs'; then
        util_log_message "Sistema de archivos raíz no es BTRFS. Omitiendo optimización."
        $DIALOG_CMD --title "Optimizar BTRFS" --msgbox "El sistema de archivos raíz no es BTRFS. Opción omitida." 8 60
        return
    fi

    if ($DIALOG_CMD --title "Optimizar BTRFS" --yesno "Se detectó BTRFS. ¿Deseas optimizar el sistema de archivos BTRFS ahora?\n(compresión ZSTD, defragmentación, balanceo)\nEsto puede tardar." 12 78); then
        util_log_message "Usuario aceptó optimizar BTRFS."
        util_run_command "Remontando / con compresión zstd:1" \
            "sudo mount -o remount,compress=zstd:1 /" \
            "✅ Partición raíz remontada con compresión zstd:1." \
            "⚠️ Error remontando / con compresión."

        util_run_command "Defragmentando / con compresión zstd" \
            "sudo btrfs filesystem defragment -r -v -czstd /" \
            "✅ Defragmentación de / completada." \
            "⚠️ Error durante la defragmentación."

        util_run_command "Iniciando balanceo de BTRFS" \
            "sudo btrfs balance start -dusage=20 -musage=20 /" \
            "✅ Balanceo de BTRFS iniciado." \
            "⚠️ Error iniciando balanceo de BTRFS."

        $DIALOG_CMD --title "Completado" --msgbox "✅ Proceso de optimización BTRFS completado/iniciado." 8 60
    else
        util_log_message "Optimización de BTRFS omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Optimización de BTRFS omitida." 8 60
    fi
}

# ==============================================================================
# APPLICATION SUPPORT AND EXTRA TOOLS
# ==============================================================================

apps_install_alternative_formats_support() {
    util_log_message "Iniciando instalación de soporte para formatos de apps alternativos."
    APP_SUPPORT_CHOICES=$($DIALOG_CMD --title "Soporte Formatos de Apps Alternativos" --checklist \
        "Selecciona el soporte a instalar:" 15 78 5 \
        "FUSE_APPIMAGE" "FUSE para AppImage" ON \
        "SNAPD" "Snapd (para paquetes Snap)" OFF \
        "GEARLEVER" "GearLever (AppImage Manager vía Flatpak)" OFF \
        "FASTFETCH" "Fastfetch (herramienta de info. sistema)" ON \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -eq 0 ]; then
        util_log_message "Opciones de soporte de apps alternativas: $APP_SUPPORT_CHOICES"
        if [[ "$APP_SUPPORT_CHOICES" == *"FUSE_APPIMAGE"* ]]; then
            util_run_command "Instalando FUSE para AppImage" "sudo dnf install -y fuse" "✅ FUSE para AppImage instalado." "⚠️ Error instalando FUSE."
        fi

        if [[ "$APP_SUPPORT_CHOICES" == *"SNAPD"* ]]; then
            util_run_command "Instalando snapd" "sudo dnf install -y snapd" "✅ Snapd instalado." "⚠️ Error instalando snapd." && \
            util_run_command "Creando enlace simbólico para snap" "sudo ln -s /var/lib/snapd/snap /snap" "✅ Enlace simbólico /snap creado." "⚠️ Error creando enlace simbólico /snap."
            $DIALOG_CMD --title "Información Snapd" --msgbox "ℹ️ Snapd instalado. Recuerda que podrías necesitar reiniciar o cerrar y volver a abrir sesión para que Snap funcione correctamente." 10 78
        fi

        if [[ "$APP_SUPPORT_CHOICES" == *"FASTFETCH"* ]]; then
            util_run_command "Instalando fastfetch" "sudo dnf install -y fastfetch" "✅ fastfetch instalado." "⚠️ Error instalando fastfetch."
        fi

        if [[ "$APP_SUPPORT_CHOICES" == *"GEARLEVER"* ]]; then
            if ! flatpak remotes | grep -q flathub; then
                util_log_message "Flathub no detectado para GearLever. Intentando agregarlo..."
                util_run_command "Agregando Flathub (dependencia GearLever)" \
                    "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" \
                    "✅ Flathub agregado/verificado." \
                    "⚠️ Error agregando Flathub." || true
            fi
            util_run_command "Instalando GearLever vía Flatpak" "flatpak install -y flathub it.mijorus.gearlever" "✅ GearLever instalado." "⚠️ Error instalando GearLever."
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Soporte para formatos de aplicaciones alternativas configurado según selección." 8 70
    else
        util_log_message "Configuración de soporte para apps alternativas cancelada."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Configuración de soporte para apps alternativas cancelada." 8 60
    fi
}

apps_install_kde_extras() {
    util_log_message "Iniciando instalación de herramientas adicionales para KDE."
    if ($DIALOG_CMD --title "Herramientas Adicionales KDE" --yesno "¿Deseas seleccionar herramientas adicionales de KDE para instalar?" 10 78); then
        KDE_EXTRAS_CHOICES=$($DIALOG_CMD --checklist "Selecciona herramientas adicionales a instalar (KDE):" 20 78 5 \
            "latte-dock" "Dock alternativo para Plasma" OFF \
            "kvantum-manager" "Gestor de temas SVG para Qt" OFF \
            "gamemode" "Optimiza el sistema para juegos" OFF \
            "zram-generator" "Configura zram automáticamente" ON \
            3>&1 1>&2 2>&3)

        exitstatus_kde=$?
        if [ $exitstatus_kde -eq 0 ] && [ -n "$KDE_EXTRAS_CHOICES" ]; then
            PACKAGES_TO_INSTALL=$(echo "$KDE_EXTRAS_CHOICES" | sed 's/"//g' | tr '\n' ' ')
            util_log_message "Herramientas KDE adicionales seleccionadas: $PACKAGES_TO_INSTALL"
            util_run_command "Instalando herramientas KDE adicionales: $PACKAGES_TO_INSTALL" \
                "sudo dnf install -y $PACKAGES_TO_INSTALL" \
                "✅ Herramientas KDE adicionales instaladas." \
                "⚠️ Error instalando algunas herramientas KDE adicionales."
        elif [ $exitstatus_kde -ne 0 ]; then
             util_log_message "Selección de herramientas KDE adicionales cancelada."
             $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Selección de herramientas KDE adicionales cancelada." 8 70
        else
            util_log_message "Ninguna herramienta KDE adicional seleccionada."
            $DIALOG_CMD --title "Información" --msgbox "ℹ️ Ninguna herramienta adicional seleccionada para instalación." 8 70
        fi
    else
        util_log_message "Instalación de herramientas KDE adicionales omitida."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Instalación de herramientas KDE adicionales omitida." 8 60
    fi
}

# ==============================================================================
# SYSTEM TWEAKS AND MISCELLANEOUS CONFIGURATIONS
# ==============================================================================

tweaks_apply_miscellaneous_settings() {
    util_log_message "Iniciando configuraciones varias del sistema."
    CONFIG_CHOICES=$($DIALOG_CMD --title "Configuraciones Varias del Sistema" --checklist \
        "Selecciona las configuraciones a aplicar:" 20 78 10 \
        "SET_HOSTNAME" "Cambiar hostname del equipo" OFF \
        "FIREFOX_PREFS" "Eliminar página de inicio Fedora en Firefox" ON \
        "DNS_OVER_TLS" "Configurar DNS-over-TLS (Cloudflare/Quad9)" ON \
        "RTC_UTC" "Configurar reloj hardware en UTC (para dual-boot)" ON \
        "CPU_MITIGATIONS" "Desactivar mitigaciones CPU (rendimiento+, seguridad-, ¡PRECAUCIÓN!)" OFF \
        "NVIDIA_MODESET" "Habilitar nvidia-drm.modeset=1 (laptops híbridos NVIDIA)" OFF \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -eq 0 ]; then
        util_log_message "Configuraciones varias seleccionadas: $CONFIG_CHOICES"

        if [[ "$CONFIG_CHOICES" == *"SET_HOSTNAME"* ]]; then
            CURRENT_HOSTNAME=$(hostname)
            NEW_HOSTNAME=$($DIALOG_CMD --inputbox "Ingresa el nuevo hostname para este equipo:" 10 60 "$CURRENT_HOSTNAME" 3>&1 1>&2 2>&3)
            hostname_status=$?
            if [ $hostname_status -eq 0 ] && [ -n "$NEW_HOSTNAME" ] && [ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
                util_run_command "Cambiando hostname a '$NEW_HOSTNAME'" \
                    "sudo hostnamectl set-hostname \"$NEW_HOSTNAME\"" \
                    "✅ Hostname cambiado a '$NEW_HOSTNAME'." \
                    "⚠️ Error cambiando hostname."
            elif [ $hostname_status -ne 0 ]; then
                util_log_message "Cambio de hostname cancelado."
                $DIALOG_CMD --title "Información" --msgbox "ℹ️ Cambio de hostname cancelado." 8 60
            elif [ -z "$NEW_HOSTNAME" ]; then
                util_log_message "Nuevo hostname vacío."
                $DIALOG_CMD --title "Información" --msgbox "ℹ️ Cambio de hostname omitido (nombre vacío)." 8 60
            else
                util_log_message "Nuevo hostname es igual al actual."
                 $DIALOG_CMD --title "Información" --msgbox "ℹ️ Hostname no cambiado (es el mismo)." 8 60
            fi
        fi

        if [[ "$CONFIG_CHOICES" == *"FIREFOX_PREFS"* ]]; then
            util_run_command "Eliminando preferencias por defecto de Firefox (Fedora)" \
                "sudo rm -f /usr/lib64/firefox/browser/defaults/preferences/firefox-redhat-default-prefs.js" \
                "✅ Preferencias por defecto de Firefox eliminadas (si existían)." \
                "⚠️ Error eliminando preferencias de Firefox (puede que no existieran)."
        fi

        if [[ "$CONFIG_CHOICES" == *"DNS_OVER_TLS"* ]]; then
            util_log_message "Configurando DNS-over-TLS."
            $DIALOG_CMD --title "Procesando" --infobox "Configurando DNS-over-TLS..." 8 60
            sudo mkdir -p /etc/systemd/resolved.conf.d
            cat <<EOF_DNS | sudo tee /etc/systemd/resolved.conf.d/99-dns-over-tls.conf > /dev/null
[Resolve]
DNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=8.8.8.8 8.8.4.4
DNSOverTLS=yes
EOF_DNS
            if [ $? -eq 0 ]; then
                util_log_message "Archivo de configuración DNS-over-TLS creado."
                util_run_command "Reiniciando systemd-resolved" \
                    "sudo systemctl restart systemd-resolved" \
                    "✅ DNS-over-TLS configurado y servicio resolved reiniciado." \
                    "⚠️ Error reiniciando systemd-resolved."
            else
                util_log_message "ERROR: Creando archivo de configuración DNS-over-TLS."
                $DIALOG_CMD --title "Error" --msgbox "⚠️ Error creando archivo de configuración para DNS-over-TLS." 10 70
            fi
        fi

        if [[ "$CONFIG_CHOICES" == *"RTC_UTC"* ]]; then
            util_run_command "Configurando reloj hardware en UTC" \
                "sudo timedatectl set-local-rtc 0" \
                "✅ Reloj del hardware configurado en UTC." \
                "⚠️ Error configurando reloj hardware en UTC."
        fi

        if [[ "$CONFIG_CHOICES" == *"CPU_MITIGATIONS"* ]]; then
            util_run_command "Desactivando mitigaciones de CPU (próximo arranque)" \
                "sudo grubby --update-kernel=ALL --args=\"mitigations=off\"" \
                "✅ Mitigaciones de CPU marcadas para desactivarse en el próximo arranque. Se requiere reiniciar." \
                "⚠️ Error configurando mitigaciones de CPU."
        fi

        if [[ "$CONFIG_CHOICES" == *"NVIDIA_MODESET"* ]]; then
            util_run_command "Habilitando nvidia-drm.modeset=1 (próximo arranque)" \
                "sudo grubby --update-kernel=ALL --args=\"nvidia-drm.modeset=1\"" \
                "✅ nvidia-drm.modeset=1 agregado a los parámetros del kernel. Se requiere reiniciar." \
                "⚠️ Error configurando nvidia-drm.modeset=1."
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Configuraciones varias del sistema aplicadas según selección." 8 70
    else
        util_log_message "Aplicación de configuraciones varias cancelada."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Aplicación de configuraciones varias cancelada." 8 60
    fi
}

# ==============================================================================
# SYSTEM MAINTENANCE AND CLEANUP FUNCTIONS
# ==============================================================================

maintenance_perform_final_cleanup() {
    util_log_message "Iniciando limpieza final del sistema."
    if ($DIALOG_CMD --title "Limpieza Final" --yesno "¿Realizar limpieza final del sistema (autoremove, update/upgrade)?\n(REQUIERE REINICIO)" 10 78); then
        util_log_message "Usuario aceptó realizar limpieza final."
        util_run_command "Ejecutando 'dnf autoremove'" \
            "sudo dnf autoremove -y" \
            "✅ 'dnf autoremove' completado." \
            "⚠️ Error en 'dnf autoremove'."

        util_run_command "Ejecutando 'dnf update/upgrade' final" \
            "sudo dnf update -y && sudo dnf upgrade -y --refresh" \
            "✅ 'dnf update/upgrade' final completado." \
            "⚠️ Error en 'dnf update/upgrade' final."

        util_log_message "Limpieza final completada. Requiere reinicio."
        $DIALOG_CMD --title "Reinicio Recomendado" --msgbox "Se recomienda reiniciar el sistema para aplicar todos los cambios y limpiar completamente.\nEl script terminará ahora." 10 70
        exit 0
    else
        util_log_message "Limpieza final del sistema omitida por el usuario."
        $DIALOG_CMD --title "Información" --msgbox "ℹ️ Limpieza final del sistema omitida." 8 60
    fi
}

maintenance_apply_stability_tasks() {
    util_log_message "Iniciando tareas de mantenimiento y estabilidad."
    MAINT_CHOICES=$($DIALOG_CMD --title "Mantenimiento y Estabilidad" --checklist \
        "Selecciona las tareas de mantenimiento a aplicar/configurar:" 20 78 10 \
        "FSTRIM_TIMER" "Habilitar fstrim.timer (limpieza SSD)" ON \
        "DISABLE_SERVICES" "Desactivar systemd-udev-settle y NetworkManager-wait-online" OFF \
        "BTRFS_SCRUB" "Ejecutar BTRFS scrub (si aplica, puede tardar)" OFF \
        "REINSTALL_GROUPS" "Reinstalar grupos base (base-x, standard, kde-desktop-environment)" OFF \
        "LM_SENSORS" "Instalar lm_sensors y psensor" ON \
        "BACKUP_ETC" "Crear respaldo de /etc" ON \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -eq 0 ]; then
        util_log_message "Tareas de mantenimiento seleccionadas: $MAINT_CHOICES"

        if [[ "$MAINT_CHOICES" == *"FSTRIM_TIMER"* ]]; then
            util_run_command "Habilitando fstrim.timer" "sudo systemctl enable --now fstrim.timer" "✅ fstrim.timer habilitado y activado." "⚠️ Error habilitando fstrim.timer."
        fi

        if [[ "$MAINT_CHOICES" == *"DISABLE_SERVICES"* ]]; then
            util_run_command "Desactivando systemd-udev-settle y NM-wait-online" \
            "sudo systemctl mask systemd-udev-settle.service && sudo systemctl disable NetworkManager-wait-online.service" \
            "✅ Servicios systemd-udev-settle y NetworkManager-wait-online desactivados/enmascarados." \
            "⚠️ Error desactivando servicios."
        fi

        if [[ "$MAINT_CHOICES" == *"BTRFS_SCRUB"* ]]; then
            if mount | grep -q 'on / type btrfs'; then
                util_run_command "Iniciando BTRFS scrub en segundo plano" "sudo btrfs scrub start -Bd /" "✅ BTRFS scrub iniciado en segundo plano." "⚠️ Error iniciando BTRFS scrub."
            else
                util_log_message "Sistema no es BTRFS, scrub omitido."
                $DIALOG_CMD --title "Información" --msgbox "ℹ️ Sistema de archivos raíz no es BTRFS, BTRFS scrub omitido." 8 70
            fi
        fi

        if [[ "$MAINT_CHOICES" == *"REINSTALL_GROUPS"* ]]; then
            util_run_command "Reinstalando grupos base" \
            "sudo dnf group install -y base-x standard kde-desktop-environment" \
            "✅ Grupos base (base-x, standard, kde-desktop-environment) reinstalados." \
            "⚠️ Error reinstalando grupos base."
        fi

        util_log_message "Verificando versión del kernel instalado:"
        KERNEL_VERSION=$(rpm -q kernel-core)
        util_log_message "Kernel instalado: $KERNEL_VERSION"
        $DIALOG_CMD --title "Info Kernel" --infobox "Kernel(s) instalados (ver log para lista completa):\n$(rpm -q kernel-core | tail -n1)" 7 70
        sleep 2


        if [[ "$MAINT_CHOICES" == *"LM_SENSORS"* ]]; then
            util_run_command "Instalando lm_sensors y psensor" "sudo dnf install -y lm_sensors psensor" "✅ lm_sensors y psensor instalados." "⚠️ Error instalando lm_sensors/psensor."
            if ($DIALOG_CMD --title "Detectar Sensores" --yesno "¿Ejecutar 'sudo sensors-detect --auto' ahora?\n(Responde YES a las preguntas si no estás seguro)" 10 78); then
                util_log_message "Ejecutando sensors-detect --auto"
                $DIALOG_CMD --infobox "Ejecutando 'sudo sensors-detect --auto' en la terminal...\nPor favor, sigue las instrucciones allí." 8 70
                sleep 2
                sudo sensors-detect --auto >> "$LOG_FILE" 2>&1
                util_log_message "sensors-detect completado."
                $DIALOG_CMD --title "Información" --msgbox "ℹ️ Detección de sensores completada. Puede que necesites reiniciar para que los módulos del kernel se carguen." 10 70
            fi
        fi

        if [[ "$MAINT_CHOICES" == *"BACKUP_ETC"* ]]; then
            BACKUP_PATH_BASE="$HOME"
            if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
                 BACKUP_PATH_BASE="/home/$SUDO_USER"
            fi
            BACKUP_FILE="etc-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
            BACKUP_PATH="$BACKUP_PATH_BASE/$BACKUP_FILE"

            util_run_command "Creando respaldo de /etc en $BACKUP_PATH" \
                "sudo tar czvf \"$BACKUP_PATH\" /etc" \
                "✅ Respaldo de /etc creado en $BACKUP_PATH." \
                "⚠️ Error creando respaldo de /etc."
            if [ -f "$BACKUP_PATH" ] && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
                sudo chown "$SUDO_USER":"$SUDO_USER" "$BACKUP_PATH"
                util_log_message "Propietario de $BACKUP_PATH cambiado a $SUDO_USER."
            fi
        fi
        $DIALOG_CMD --title "Completado" --msgbox "✅ Tareas de mantenimiento y estabilidad completadas según selección." 8 70
    else
        util_log_message "Tareas de mantenimiento y estabilidad canceladas."
        $DIALOG_CMD --title "Cancelado" --msgbox "ℹ️ Tareas de mantenimiento y estabilidad canceladas." 8 60
    fi
}

# ==============================================================================
# SCRIPT EXECUTION START
# ==============================================================================

core_check_root_privileges
core_check_dialog_utility

# Inform user about the log file at the beginning
$DIALOG_CMD --title "Información Inicial" --msgbox "Bienvenido al script de post-instalación de Fedora KDE.\n\nSe registrarán logs detallados en:\n$LOG_FILE" 10 70

core_check_internet_connection

# ==============================================================================
# MAIN MENU
# ==============================================================================
while :; do
    clear
    OPCION=$($DIALOG_CMD --title "Menú Post-Instalación Fedora KDE" \
        --menu "Selecciona una opción (Log: $LOG_FILE):" 25 78 18 \
        "A" "Configurar DNF Personalizado" \
        "B" "Configurar Repositorios Adicionales (RPMFusion, Flathub, etc.)" \
        "C" "Actualización Inicial del Sistema (REQUIERE REINICIO)" \
        "D" "Actualizar Firmware del Sistema (LVFS)" \
        "E" "Instalar Códecs Multimedia Completos" \
        "F" "Configurar Drivers Gráficos y Aceleración" \
        "G" "Optimizar Sistema de Archivos Btrfs" \
        "H" "Instalar Soporte H.264 (OpenH264)" \
        "I" "Instalar Soporte DVDs y Firmwares (Tainted)" \
        "J" "Instalar Soporte Formatos de Apps Alternativos (AppImage, Snap)" \
        "K" "Aplicar Configuraciones Varias del Sistema" \
        "L" "Realizar Limpieza Final del Sistema (REQUIERE REINICIO)" \
        "M" "Aplicar Tareas de Mantenimiento y Estabilidad" \
        "N" "Instalar Herramientas Adicionales para KDE" \
        "S" "SALIR" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
        util_log_message "Menú principal cancelado por el usuario. Solicitando confirmación para salir..."
        $DIALOG_CMD --title "Saliendo" --yesno "¿Estás seguro de que deseas salir del script?" 8 60
        if [ $? -eq 0 ]; then
            echo "🚪 Saliendo del script." | tee -a "$LOG_FILE"
            exit 0
        else
            continue
        fi
    fi

    util_log_message "Opción del menú principal seleccionada: $OPCION"
    case $OPCION in
        A) system_configure_dnf ;;
        B) system_configure_repositories ;;
        C) system_perform_initial_update ;; # This function might call exit 0
        D) system_update_firmware_lvfs ;;
        E) media_install_codecs ;;
        F) media_configure_graphics_drivers ;;
        G) storage_optimize_btrfs ;;
        H) media_install_h264_support ;;
        I) media_install_dvd_and_tainted_firmware ;;
        J) apps_install_alternative_formats_support ;;
        K) tweaks_apply_miscellaneous_settings ;;
        L) maintenance_perform_final_cleanup ;; # This function might call exit 0
        M) maintenance_apply_stability_tasks ;;
        N) apps_install_kde_extras ;;
        S)
            $DIALOG_CMD --title "Saliendo" --yesno "¿Estás seguro de que deseas salir del script?" 8 60
            if [ $? -eq 0 ]; then
                util_log_message "Saliendo del script por selección del usuario."
                echo "👋 Saliendo del script de post-instalación." | tee -a "$LOG_FILE"
                exit 0
            fi
            ;;
        *)
            util_log_message "Opción inválida seleccionada: $OPCION"
            $DIALOG_CMD --title "Error" --msgbox "❌ Opción inválida." 6 30 ;;
    esac
done

util_log_message "=== Fin del Script de Post-Instalación Fedora ==="
exit 0

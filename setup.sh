#!/bin/bash

# #############################################################################
# SCRIPT DE POST-INSTALACIÓN FEDORA 42 KDE PLASMA (ASUS TUF Dash F15 FX517ZE)
# Autor: Tu Nombre/Nick (Adaptado por IA Asistente)
# Versión: 1.1
#
# IMPORTANTE:
# 1. EJECUTA ESTE SCRIPT BAJO TU PROPIO RIESGO.
# 2. REVISA CADA SECCIÓN CUIDADOSAMENTE ANTES DE EJECUTAR.
# 3. ALGUNAS ACCIONES REQUIEREN REINICIO O RE-LOGUEO AL FINAL.
# #############################################################################

# --- Variables de Configuración (Ajusta según sea necesario) ---
TARGET_USER=$(logname) # O el usuario principal si se ejecuta como root desde el inicio
TARGET_USER_HOME="/home/$TARGET_USER"
# USER_CONFIG_DIR="$TARGET_USER_HOME/dotfiles" # Descomenta y ajusta si tienes tus dotfiles en una carpeta específica

# --- Funciones de Ayuda ---
print_message() {
  echo ""
  echo "================================================================================"
  echo "== $1"
  echo "================================================================================"
  echo ""
  sleep 2
}

log_info() { echo -e "\e[34mINFO:\e[0m $1"; }
log_warn() { echo -e "\e[33mWARN:\e[0m $1"; }
log_error() { echo -e "\e[31mERROR:\e[0m $1"; }
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# --- Pedir contraseña de sudo al inicio y mantenerla viva ---
if ! sudo -v; then
    log_error "Se requieren privilegios de sudo. Saliendo."
    exit 1
fi
# Mantener sudo vivo
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# --- Determinar archivo de perfil del usuario ---
PROFILE_FILE="$TARGET_USER_HOME/.bashrc"
if [ -f "$TARGET_USER_HOME/.zshrc" ]; then
    PROFILE_FILE="$TARGET_USER_HOME/.zshrc"
fi
log_info "Archivo de perfil detectado/seleccionado: $PROFILE_FILE"

# #################################################
# SECCIÓN A: OPTIMIZACIÓN DNF, REPOSITORIOS Y ACTUALIZACIÓN INICIAL
# #################################################
print_message "SECCIÓN A: Optimizando DNF, Configurando Repositorios y Actualización Inicial"

log_info "Optimizando configuración de DNF..."
if ! grep -q "fastestmirror=True" /etc/dnf/dnf.conf; then
    echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf
fi
if ! grep -q "max_parallel_downloads=10" /etc/dnf/dnf.conf; then
    echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf
fi
# Descomentar con precaución:
# if ! grep -q "defaultyes=True" /etc/dnf/dnf.conf; then
#     echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf # Acepta automáticamente todas las preguntas de DNF
# fi

log_info "Habilitando Repositorios RPM Fusion (Free y Nonfree)..."
sudo dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf config-manager --set-enabled rpmfusion-free-updates-testing rpmfusion-nonfree-updates-testing # Habilitar repos testing (opcional)

log_info "Habilitando Repositorio Terra..."
sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release

log_info "Habilitando Repositorio Flathub..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log_info "Instalando y Habilitando Soporte Snapd..."
sudo dnf install -y snapd
if [ ! -L /snap ]; then # Solo crear el enlace simbólico si no existe
    sudo ln -s /var/lib/snapd/snap /snap
fi
sudo systemctl enable --now snapd.socket

log_info "Instalando COPR CLI..."
sudo dnf install -y copr-cli

log_info "Habilitando COPR para ASUS Linux Tools (asusctl, supergfxctl)..."
sudo dnf copr enable -y lukenukem/asus-linux

log_info "Habilitando COPR para Kernel ASUS CachyOS..."
sudo dnf copr enable -y lukenukem/asus-kernel

log_info "Habilitando Repositorio Negativo17 para Drivers NVIDIA y Multimedia..."
sudo dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-nvidia.repo
sudo dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

log_info "Añadiendo Repositorio Oficial de Docker..."
sudo dnf config-manager addrepo --from-repofile="https://download.docker.com/linux/fedora/docker-ce.repo" || log_warn "Fallo al añadir repo de Docker oficial."

log_info "Actualizando el sistema y metadatos de repositorios..."
sudo dnf upgrade --refresh -y
sudo dnf groupupdate -y core # Asegura que el grupo base está actualizado

# #################################################
# SECCIÓN B: SISTEMA BASE - DRIVERS, FIRMWARE, KERNEL, MULTIMEDIA
# #################################################
print_message "SECCIÓN B: Configurando Sistema Base (Drivers, Firmware, Kernel, Multimedia)"

log_info "Actualizando Firmware del sistema..."
sudo fwupdmgr refresh --force
sudo fwupdmgr get-devices
sudo fwupdmgr get-updates
sudo fwupdmgr update -y

log_info "Instalando Drivers NVIDIA desde Negativo17 con soporte CUDA y multimedia..."
# Instalar dkms asegura que los módulos se recompilen con actualizaciones de kernel
sudo dnf install -y \
  xorg-x11-drv-nvidia-dkms \
  nvidia-modprobe \
  nvidia-settings \
  nvidia-driver-cuda \
  libva-nvidia-driver
  # nvidia-cuda-toolkit es muy grande, considera instalarlo solo si lo necesitas para desarrollo CUDA
  # ffmpeg-nvidia y gstreamer1-plugins-bad-freeworld se instalarán con el grupo multimedia más adelante

log_info "Instalando Kernel parcheado para ASUS (CachyOS)..."
sudo dnf install -y kernel-rog-cachyos kernel-rog-cachyos-devel kernel-rog-cachyos-headers

log_info "Instalando Herramientas ASUS (asusctl y supergfxctl)..."
sudo dnf install -y asusctl supergfxctl asusctl-rog-gui
log_info "Habilitando servicio supergfxd para gestión de GPU híbrida..."
sudo systemctl enable --now supergfxd.service

log_info "Instalando Codecs Multimedia y Librerías Esenciales..."
sudo dnf groupinstall -y --allowerasing --skip-broken multimedia sound-and-video
sudo dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-libav \
                    lame\* --exclude=lame-devel \
                    libdvdcss ffmpegthumbnailer libva-utils vdpauinfo \
                    libavcodec-freeworld # De RPM Fusion para H.264/H.265

log_info "Instalando soporte para paquetes de 32 bits (para Wine, Steam, etc.)..."
sudo dnf install -y glibc.i686 libstdc++.i686 mesa-libGL.i686 mesa-libEGL.i686 \
                    mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 \
                    pipewire-alsa.i686 alsa-lib.i686 \
                    libX11.i686 libXext.i686 libXrandr.i686 libXfixes.i686 \
                    fontconfig.i686 freetype.i686 \
                    xorg-x11-drv-nvidia-libs.i686 # Para NVIDIA 32-bit

# #################################################
# SECCIÓN C: UTILIDADES Y HERRAMIENTAS COMUNES
# #################################################
print_message "SECCIÓN C: Instalando Utilidades y Herramientas Comunes"

sudo dnf install -y htop fastfetch nano unzip p7zip p7zip-plugins \
                    gnome-disk-utility file-roller ark kio-fuse kio-gdrive \
                    ffmpeg fuse # fuse para AppImage

log_info "Instalando Grupos de Desarrollo y Sistema recomendados..."
sudo dnf groupinstall -y admin-tools c-development desktop-accessibility development-tools system-tools python-science
sudo dnf install -y vlc # VLC como reproductor

# #################################################
# SECCIÓN D: HERRAMIENTAS DE DESARROLLO Y VIRTUALIZACIÓN
# #################################################
print_message "SECCIÓN D: Herramientas de Desarrollo y Virtualización"

log_info "Instalando Git..."
sudo dnf install -y git

log_info "Instalando Python (asegurando pip y venv)..."
sudo dnf install -y python3 python3-pip python3-devel python3-virtualenv

log_info "Instalando Java (OpenJDK), Maven y Ant+Ivy..."
sudo dnf install -y java-devel java-openjdk-headless java-openjdk maven ant apache-ivy

log_info "Instalando Golang y configurando PATH..."
sudo dnf install -y golang
sudo -u "$TARGET_USER" mkdir -p "$TARGET_USER_HOME/go"
if ! grep -q 'export GOPATH=' "$PROFILE_FILE"; then
    echo 'export GOPATH=$HOME/go' | sudo -u "$TARGET_USER" tee -a "$PROFILE_FILE" > /dev/null
fi
if ! grep -q 'export PATH=.*$GOPATH/bin' "$PROFILE_FILE"; then
    echo 'export PATH=$PATH:$GOPATH/bin' | sudo -u "$TARGET_USER" tee -a "$PROFILE_FILE" > /dev/null
fi
log_info "GOPATH y PATH para Golang configurados. Re-logueo o 'source $PROFILE_FILE' necesario."

log_info "Instalando Node.js (vía módulo DNF) y Yarn..."
sudo dnf module install -y nodejs
sudo dnf install -y yarnpkg
log_info "Configurando directorio global de npm y PATH..."
sudo -u "$TARGET_USER" mkdir -p "$TARGET_USER_HOME/.npm-global"
sudo -u "$TARGET_USER" npm config set prefix "$TARGET_USER_HOME/.npm-global"
if ! grep -q 'export PATH=.*\.npm-global/bin' "$PROFILE_FILE"; then
    echo 'export PATH=$HOME/.npm-global/bin:$PATH' | sudo -u "$TARGET_USER" tee -a "$PROFILE_FILE" > /dev/null
fi
log_info "PATH para npm configurado. Re-logueo o 'source $PROFILE_FILE' necesario."

log_info "Instalando Bun (runtime de JavaScript)..."
if command -v bun &>/dev/null; then
    log_info "Bun ya está instalado."
else
    log_warn "Se procederá a descargar y ejecutar el script de instalación de Bun."
    read -r -p "¿Desea continuar? [S/n]: " confirm_bun
    confirm_bun=${confirm_bun:-S}
    if [[ "$confirm_bun" =~ ^[Ss]$ ]]; then
        if sudo -u "$TARGET_USER" curl -fsSL https://bun.sh/install | bash; then
            log_info "Bun instalado. Re-logueo o nueva terminal para usar 'bun'."
        else
            log_warn "Fallo en la instalación de Bun."
        fi
    else
        log_info "Instalación de Bun cancelada."
    fi
fi

log_info "Instalando soporte de virtualización (KVM/QEMU/libvirt)..."
VIRT_SUPPORT_DETECTED=$(grep -E -c '(vmx|svm)' /proc/cpuinfo)
if [ "$VIRT_SUPPORT_DETECTED" -gt 0 ]; then
     log_info "Soporte de virtualización por hardware detectado."
     sudo dnf install -y @virtualization qemu-kvm-core libvirt virt-install cockpit-machines guestfs-tools
else
     log_warn "No se detectó soporte de virtualización por hardware. El rendimiento puede ser limitado."
     sudo dnf install -y @virtualization qemu-kvm-core libvirt virt-install cockpit-machines guestfs-tools
fi
sudo systemctl enable --now libvirtd || log_warn "Fallo al habilitar/iniciar libvirtd."
log_info "Añadiendo usuario '$TARGET_USER' al grupo libvirt..."
if ! groups "$TARGET_USER" | grep -q '\blibvirt\b'; then
    sudo usermod -aG libvirt "$TARGET_USER" || log_warn "Fallo al añadir '$TARGET_USER' a libvirt."
    log_info "Usuario '$TARGET_USER' añadido a libvirt. Re-logueo necesario."
else
    log_info "Usuario '$TARGET_USER' ya pertenece a libvirt."
fi

log_info "Instalando Docker Engine (v2) desde el repositorio oficial de Docker..."
# El repo ya fue añadido en SECCIÓN A
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker || log_warn "Fallo al habilitar/iniciar docker."
log_info "Añadiendo usuario '$TARGET_USER' al grupo docker..."
if ! groups "$TARGET_USER" | grep -q '\bdocker\b'; then
    sudo groupadd docker &>/dev/null # Crea el grupo si no existe
    sudo usermod -aG docker "$TARGET_USER" || log_warn "Fallo al añadir '$TARGET_USER' a docker."
    log_info "Usuario '$TARGET_USER' añadido a docker. Re-logueo necesario para usar 'docker' sin sudo."
else
    log_info "Usuario '$TARGET_USER' ya pertenece a docker."
fi

# #################################################
# SECCIÓN E: CONFIGURACIÓN DE TERMINAL (ZSH, OH MY ZSH, POWERLEVEL10K)
# #################################################
print_message "SECCIÓN E: Configurando Terminal Personalizada"

log_info "Instalando Zsh (si no está ya instalado)..."
sudo dnf install -y zsh

log_info "Configurando Oh My Zsh y Powerlevel10k para el usuario '$TARGET_USER'..."
OHMYZSH_DIR="$TARGET_USER_HOME/.oh-my-zsh"
P10K_THEME_DIR="$OHMYZSH_DIR/custom/themes/powerlevel10k"

if [ ! -d "$OHMYZSH_DIR" ]; then
    log_info "Instalando Oh My Zsh..."
    # Ejecutar el instalador de Oh My Zsh como el usuario, no como root
    # El instalador de Oh My Zsh intentará cambiar la shell por defecto.
    # Es más seguro que el usuario lo haga manualmente después.
    sudo -u "$TARGET_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_info "Oh My Zsh instalado. Puede que necesites re-loguearte para que Zsh sea tu shell por defecto."
else
    log_info "Oh My Zsh ya parece estar instalado."
fi

log_info "Clonando tema Powerlevel10k..."
if [ ! -d "$P10K_THEME_DIR" ]; then
    sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_THEME_DIR" || log_warn "Fallo al clonar Powerlevel10k."
else
    log_info "Powerlevel10k ya clonado."
fi

log_info "Copiando archivos de configuración locales (.zshrc, .p10k.zsh)..."
# Asumimos que USER_CONFIG_DIR está definido y contiene tus dotfiles
if [ -n "$USER_CONFIG_DIR" ] && [ -d "$USER_CONFIG_DIR" ]; then
    if [ -f "$USER_CONFIG_DIR/.zshrc" ]; then
        log_info "Copiando .zshrc..."
        if [ -f "$TARGET_USER_HOME/.zshrc" ] && [ ! -L "$TARGET_USER_HOME/.zshrc" ]; then
            sudo -u "$TARGET_USER" mv "$TARGET_USER_HOME/.zshrc" "$TARGET_USER_HOME/.zshrc.bak_$(date +%Y%m%d_%H%M%S)"
        fi
        sudo -u "$TARGET_USER" cp "$USER_CONFIG_DIR/.zshrc" "$TARGET_USER_HOME/.zshrc"
        log_info ".zshrc local copiado."
    else
        log_warn "No se encontró .zshrc en $USER_CONFIG_DIR. Oh My Zsh usará su plantilla."
    fi

    if [ -f "$USER_CONFIG_DIR/.p10k.zsh" ]; then
        log_info "Copiando .p10k.zsh..."
        if [ -f "$TARGET_USER_HOME/.p10k.zsh" ] && [ ! -L "$TARGET_USER_HOME/.p10k.zsh" ]; then
            sudo -u "$TARGET_USER" mv "$TARGET_USER_HOME/.p10k.zsh" "$TARGET_USER_HOME/.p10k.zsh.bak_$(date +%Y%m%d_%H%M%S)"
        fi
        sudo -u "$TARGET_USER" cp "$USER_CONFIG_DIR/.p10k.zsh" "$TARGET_USER_HOME/.p10k.zsh"
        log_info ".p10k.zsh local copiado."
    else
        log_warn "No se encontró .p10k.zsh en $USER_CONFIG_DIR. Powerlevel10k usará su asistente."
    fi
else
    log_warn "La variable USER_CONFIG_DIR no está definida o el directorio no existe. Saltando copia de dotfiles personalizados."
    log_warn "Oh My Zsh y Powerlevel10k usarán sus configuraciones por defecto o asistentes."
fi

log_warn "Para cambiar tu shell por defecto a Zsh, ejecuta manualmente: ${COLOR_GREEN}chsh -s \$(which zsh)${COLOR_RESET}"
log_warn "Después necesitarás ${COLOR_RED}cerrar y volver a iniciar sesión${COLOR_RESET}."

# #################################################
# SECCIÓN F: INSTALACIÓN DE APLICACIONES (FLATPAK, SNAP, RPM ADICIONALES)
# #################################################
print_message "SECCIÓN F: Instalando Aplicaciones Adicionales"

log_info "Instalando Wine (RPM, ya debería estar de la sección C)..."
# Ya instalado arriba, pero se puede verificar
sudo dnf install -y wine winetricks

log_info "Instalando Visual Studio Code (RPM, ya debería estar)..."
# Ya instalado arriba
sudo dnf install -y code

log_info "Instalando aplicaciones Flatpak de Flathub..."
# Usar 'sudo -u' para instalar como usuario es generalmente más seguro para Flatpaks si no necesitas acceso de root para la app.
# Si prefieres instalación a nivel de sistema, quita 'sudo -u "$TARGET_USER"' y '--user'.
sudo -u "$TARGET_USER" flatpak install -y --noninteractive flathub \
    com.spotify.Client \
    com.obsproject.Studio \
    org.onlyoffice.desktopeditors \
    com.usebottles.bottles \
    com.microsoft.Edge \
    org.audacityteam.Audacity \
    cc.arduino.IDE2 \
    com.bitwarden.desktop \
    it.mijorus.gearlever \
    org.freedesktop.Platform.GL.default \
    org.freedesktop.Platform.VAAPI.Intel \
    org.freedesktop.Platform.openh264 \
    org.kde.Platform # Runtimes comunes

log_info "Instalando Flatpaks del repositorio Fedora..."
sudo -u "$TARGET_USER" flatpak install -y --noninteractive fedora \
    org.eclipse.Java \
    com.github.tchx84.Flatseal \
    org.gtk.Gtk3theme.Breeze # Y otros que necesites

log_info "Instalando aplicaciones Snap..."
if systemctl is-active --quiet snapd; then
    # --classic permite a las snaps tener más acceso, necesario para algunas como Android Studio
    sudo snap install android-studio --classic || log_warn "Fallo al instalar Android Studio (snap)."
    sudo snap install core22 || log_warn "Falló la instalación de core22 (snap base)."
    # Añade aquí otras aplicaciones Snap que necesites
else
    log_warn "Servicio snapd no activo. Saltando instalación de snaps."
fi

# #################################################
# FINALIZACIÓN
# #################################################
print_message "Finalizando y Limpiando"

log_info "Limpiando caché de DNF..."
sudo dnf clean all

log_info "Actualizando GRUB (importante si se instaló un nuevo kernel)..."
if [ -d /sys/firmware/efi ]; then
    sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
else
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
fi

print_message "¡Script de post-instalación completado!"
log_warn "Algunos cambios como la pertenencia a nuevos grupos (docker, libvirt), variables de entorno (GOPATH, NPM_PATH)"
log_warn "y el cambio de shell a Zsh requieren que ${COLOR_RED}CIERRES SESIÓN Y VUELVAS A INICIARLA${COLOR_RESET}."
log_warn "Un ${COLOR_RED}REINICIO COMPLETO${COLOR_RESET} es altamente recomendable para aplicar los cambios de kernel y drivers NVIDIA."

echo ""
read -r -p "¿Desea reiniciar el sistema ahora? (s/N): " respuesta
if [[ "$respuesta" =~ ^([sS][iI]|[sS]|[yY][eE][sS]|[yY])$ ]]; then
    log_info "Reiniciando el sistema..."
    sudo reboot
else
    log_info "No se reiniciará automáticamente. Por favor, reinicia manualmente cuando estés listo."
fi

exit 0

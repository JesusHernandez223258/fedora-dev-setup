# README: Guía post-install para Fedora (post-install / setup)

**Propósito:** Guía modular y reproducible para dejar una instalación de Fedora (Workstation/Kinoite/Silverblue) en un estado estable, compatible y preparada para uso diario y desarrollo. Diseñada para ser usada como `README.md` en un repositorio Git que contenga scripts y notas.

---

## Índice

1. Introducción
2. Precauciones y prerequisitos
3. Repositorios y third-party (RPM Fusion, Flathub, otros)
4. Actualización inicial y firmware
5. Layout Btrfs y Timeshift (snapshots)
6. Drivers gráficos (NVIDIA) y firmware adicionales
7. Códecs multimedia y soporte de audio/video
8. Flatpak / Snap / AppImage — gestión y herramientas
9. Herramientas básicas y utilidades (CLI/GUI)
10. Configuración hardware-específica (ASUS / ROG)
11. Montado y permisos de discos externos (compatibilidad Windows)
12. Backup, snapshots y rollback (Timeshift, rsync, borg)
13. Kernels personalizados — riesgo y rollback
14. Desarrollo: runtimes, SDKs, Docker, lenguajes
15. Automatización: scripts postinstall y Ansible
16. Validación y pruebas
17. FAQ & Troubleshooting
18. Cambios / Changelog

---

## 1. Introducción

Breve descripción del objetivo del repo y cómo usar esta guía: pasos recomendados en orden (repos → actualización → drivers → backups → personalización → dev).

## 2. Precauciones y prerequisitos

* Tener copia de seguridad (si ya existen datos importantes).
* Entender UEFI vs legacy y Secure Boot (si se usan drivers propietarios: Secure Boot puede requerir firmar módulos).
* Tener conexión a Internet y permiso `sudo`.

## 3. Repositorios y third-party

**Objetivo:** habilitar repositorios necesarios que no vienen por defecto para codecs, drivers y software propietario.

### Repositorios recomendados

* RPM Fusion (free + nonfree) — para drivers NVIDIA, códecs y paquetes no empaquetados en Fedora.
* Flathub — repositorio Flatpak para aplicaciones de escritorio.
* (Opcional) Copias de seguridad de repos personales o repos de terceros según necesidad.

### Comandos de ejemplo

```bash
# RPM Fusion (instalación por DNF - ejemplo para Fedora 42+)
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Habilitar Flathub (si no está habilitado)
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

**Notas de seguridad:** revisar las fuentes antes de añadir repos. Mantener actualizado el GPG y firmas de paquetes.

## 4. Actualización inicial y firmware

* Actualizar metadatos y paquetes del sistema inmediatamente después de habilitar repos.

```bash
sudo dnf upgrade --refresh -y
sudo dnf install -y fwupd
# Actualizar firmware (interactivo)
sudo fwupdmgr get-devices && sudo fwupdmgr refresh && sudo fwupdmgr update
```

## 5. Layout Btrfs y Timeshift (snapshots)

**Contexto:** Timeshift en modo BTRFS exige una estructura con subvolúmenes nombrados `@` y opcionalmente `@home` para que funcione correctamente.

### Recomendación general

* Si tu instalación ya usa BTRFS con subvolúmenes distintos, crear o renombrar los subvolúmenes para que Timeshift los detecte.

### Comandos de ejemplo (desde live USB si es necesario)

```bash
# Montar la partición btrfs y crear subvolúmenes
sudo mount /dev/sdXn /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
# Ajustar fstab para montar subvol=@ en / y subvol=@home en /home
# Ejemplo fstab entry:
# UUID=XXX / btrfs defaults,subvol=@,compress=zstd:3,space_cache=v2 0 0
```

**Configurar Timeshift**: elegir *BTRFS* como modo y seleccionar la partición que contiene los subvolúmenes. Configurar retención y programaciones.

## 6. Drivers gráficos (NVIDIA) y firmware adicionales

**VPN / NVIDIA:** Instalar los paquetes recomendados por RPM Fusion para tarjetas NVIDIA.

```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
# Instalar utilidades relacionadas
sudo dnf install nvidia-settings
```

**Secure Boot:** si está activado, puede requerir firmar los módulos o desactivar Secure Boot.

## 7. Códecs multimedia y soporte de audio/video

Instalar paquetes multimedia desde RPM Fusion.

```bash
sudo dnf groupupdate -y multimedia
sudo dnf install -y gstreamer1-plugins-{bad-free,good,ugly} gstreamer1-libav ffmpeg
```

## 8. Flatpak / Snap / AppImage — gestión y herramientas

* Instalar Flatpak y Flathub (ver sección 3).
* Recomendar `flatseal` o `Flatpak permission manager` para gestionar permisos.

```bash
sudo dnf install -y flatpak
flatpak install flathub com.github.tchx84.Flatseal
```

## 9. Herramientas básicas y utilidades (CLI/GUI)

Lista recomendada (ejemplo): `htop btop neofetch fastfetch git vim curl wget unzip p7zip-nonfree`.

```bash
sudo dnf install -y htop btop git vim curl wget p7zip
```

## 10. Configuración hardware-específica (ASUS / ROG)

* Herramientas: `asusctl`, `rog-core`, `asus-headers` (según disponibilidad), y `asusctl` GUI.
* Algunas funcionalidades dependen de módulos/kernels parcheados (ej.: `asus_armoury` o parches ROG). Si se usan kernels externos (CachyOS/Cachy kernel) hay que considerar riesgos.

## 11. Montado y permisos de discos externos (compatibilidad Windows)

**Objetivo:** permitir ejecutar proyectos desde un disco formateado en NTFS sin errores de permisos al compilar.

* Montar con `ntfs-3g` y opciones adecuadas:

```bash
sudo dnf install -y ntfs-3g
sudo mkdir -p /mnt/windows_disk
sudo mount -t ntfs-3g -o uid=1000,gid=1000,umask=022 /dev/sdXY /mnt/windows_disk
```

* Ajustar `uid`/`gid`/`fmask`/`dmask` según necesidad para que usuarios puedan ejecutar scripts y compilar.

## 12. Backup, snapshots y rollback

* Timeshift (btrfs) + rsync remoto o borg para copias de seguridad de datos. Configurar periodicidad y retención.

## 13. Kernels personalizados — riesgo y rollback

* Explicar riesgos: incompatibilidades, necesidad de reinstalar drivers, riesgo de no bootear.
* Recomendación: mantener al menos un kernel stock y firmar módulos si usas Secure Boot.
* Procedimiento de rollback: conservar initramfs y un kernel alternativo en GRUB; crear snapshot con Timeshift antes de cambiar kernel.

## 14. Desarrollo: runtimes, SDKs, Docker, lenguajes

* Instalar dnf group/package para desarrolladores, ejemplo:

```bash
sudo dnf install -y @development-tools @cdevelopment
sudo dnf install -y docker docker-compose
# SDKs y lenguajes
dnf install -y java-17-openjdk-devel python3 python3-virtualenv golang rust cargo nodejs
```

## 15. Automatización: scripts postinstall y Ansible

* Recomendar crear scripts `postinstall.sh` y/o usar Ansible playbook para reproducibilidad.
* Estructura del repo: `scripts/`, `ansible/`, `docs/`, `README.md`.

## 16. Validación y pruebas

* Lista rápida de verificaciones: `dnf check`, probar GPU con `glxinfo`/`vulkaninfo`, probar audio, comprobar snapshots Timeshift, comprobar montaje NTFS.

## 17. FAQ & Troubleshooting

* Errores comunes y soluciones rápidas (ej.: Secure Boot + NVIDIA → firmar módulos; Timeshift no detecta BTRFS → revisar subvol names).

## 18. Changelog

* Mantener un `CHANGELOG.md` donde se anote cada cambio de la guía o de scripts.

---

## Anexos: scripts de ejemplo

* `scripts/postinstall.sh` (plantilla) — instalar repos, actualizar, instalar paquetes básicos.
* `scripts/create-btrfs-subvols.sh` — ejemplo para crear `@` y `@home` desde live USB.

---

*Versión inicial: 0.1 — creado como borrador. Revisión: documentar pruebas y añadir secciones específicas por modelo de laptop (ASUS ROG) y ejemplos de `fstab` reales según configuración del usuario.*

<!-- Fin del README -->

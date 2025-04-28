
Asegúrate de tener la carpeta `config` con los archivos de configuración de ejemplo en el mismo directorio que el script `setup.sh`. Puedes modificar estos archivos (`dnf.conf`, `.zshrc`, `.p10k.zsh`) para personalizar la configuración antes de ejecutar el script.

## Cómo Usar

1.  **Clonar/Descargar el repositorio:** Obtén los archivos del script y la carpeta `config`.
2.  **Dar permisos de ejecución:** Abre una terminal en el directorio donde guardaste los archivos y ejecuta:
    ```bash
    chmod +x setup.sh
    ```
3.  **Ejecutar las fases del script:** Ejecuta el script con `sudo`, especificando la fase que deseas ejecutar. **Sigue la secuencia recomendada y realiza los pasos intermedios (reinicios/re-login) cuando se te indique.**

### Secuencia de Ejecución Recomendada

Ejecuta los siguientes comandos *uno por uno* en el orden listado, siguiendo cuidadosamente las instrucciones que aparecen en la terminal después de cada fase.

1.  **Fase 1: Configuración Inicial, Repositorios, Herramientas Básicas, Firmware**
    ```bash
    sudo ./setup.sh phase1
    ```
    *   Configura `/etc/dnf/dnf.conf`.
    *   Instala herramientas básicas (`git`, `unzip`, etc.).
    *   Habilita repositorios (RPMFusion, COPR CLI, Terra, Flatpak, Snap).
    *   Actualiza el sistema.
    *   Actualiza el firmware.
    *   **¡IMPORTANTE!** Al finalizar, el script te pedirá **REINICIAR** el sistema. Debes hacerlo antes de continuar con la Fase 2. El script saldrá automáticamente.

2.  **Fase 2: Soporte del Sistema y Entorno de Desarrollo Base**
    ```bash
    sudo ./setup.sh phase2
    ```
    *   **Detecta tu hardware (GPU, Virtualización).**
    *   Instala drivers gráficos (Nvidia si se detecta y confirmas, o firmware para AMD/Intel).
    *   Instala soporte multimedia y codecs.
    *   Instala grupos de software comunes (herramientas de admin, desarrollo, etc.).
    *   Instala soporte de virtualización (KVM/QEMU/libvirt) y añade tu usuario al grupo `libvirt`.
    *   Instala Docker y añade tu usuario al grupo `docker`.
    *   Instala lenguajes y herramientas de desarrollo (Java, Maven, Ant, Golang, Node.js, Yarn, Bun - este último con confirmación).
    *   Configura variables de entorno (GOPATH, PATH para Node/npm/Bun) en tu archivo de perfil (`.bashrc` o `.zshrc`).
    *   **¡IMPORTANTE!** Al finalizar, el script te indicará que **CIERRES Y VUELVAS A INICIAR TU SESIÓN** (o reinicies completamente) para que los cambios de grupo y las variables de entorno surtan efecto. Debes hacerlo antes de continuar con la Fase 3. El script saldrá automáticamente.

3.  **Fase 3: Configuración de Terminal y Aplicaciones**
    ```bash
    sudo ./setup.sh phase3
    ```
    *   Instala Zsh.
    *   Solicita confirmación para cambiar tu shell por defecto a Zsh (te dará el comando para ejecutarlo manualmente, que es lo más seguro).
    *   Configura Oh My Zsh y clona Powerlevel10k.
    *   Copia tus archivos de configuración local (`.zshrc`, `.p10k.zsh`) a tu directorio `$HOME`.
    *   Instala aplicaciones Flatpak de Flathub y Fedora remote.
    *   Instala aplicaciones Snap.
    *   **¡IMPORTANTE!** Al finalizar, el script te indicará que **CIERRES Y VUELVAS A INICIAR TU SESIÓN** (o reinicies completamente) para que la nueva shell Zsh, la configuración de Oh My Zsh/Powerlevel10k y las aplicaciones instaladas estén disponibles en tu entorno de escritorio/terminal. Debes hacerlo antes de continuar con la Fase 4 (si la vas a ejecutar). El script saldrá automáticamente.

4.  **Fase 4 (OPCIONAL): Configuración de Secure Boot**
    ```bash
    sudo ./setup.sh phase4
    ```
    *   **¡ATENCIÓN!** Esta fase es OPCIONAL y solo necesaria si tienes Secure Boot habilitado en tu UEFI/BIOS y necesitas que módulos del kernel no firmados (como los drivers Nvidia propietarios) funcionen correctamente.
    *   Solicita confirmación antes de proceder.
    *   Instala herramientas de Secure Boot.
    *   Genera una clave MOK local.
    *   Importa la clave pública en la lista de claves MOK (esto requiere que introduzcas una contraseña durante la ejecución del script).
    *   **¡CRÍTICO!** Al finalizar, el script te mostrará **INSTRUCCIONES DETALLADAS Y CRÍTICAS** sobre los pasos MANUALES que debes seguir **INMEDIATAMENTE DESPUÉS DE REINICIAR**. Debes interactuar con la pantalla de MOK Management antes de que Fedora inicie para completar la importación de la clave usando la contraseña que ingresaste.
    *   Después de completar los pasos manuales de MOK Management, es posible que el sistema te pida **REINICIAR** de nuevo.

### Mostrar Secuencia Completa

Si solo quieres ver un resumen de la secuencia de fases y los pasos intermedios requeridos, puedes usar el argumento `all`:

```bash
./setup.sh all
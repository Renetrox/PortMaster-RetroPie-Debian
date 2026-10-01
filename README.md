# PortMaster para RetroPie en Debian
<img width="640" height="480" alt="Captura de pantalla_2026-07-21_17-28-53" src="https://github.com/user-attachments/assets/04568228-7d63-42d7-95fb-a32657fb7baf" />

Módulo experimental de RetroPie-Setup para instalar y adaptar
[PortMaster](https://github.com/PortsMaster/PortMaster-GUI) en Debian.

Probado actualmente en:

- Debian 12 x86_64
- Debian 12 ARM64
- Orange Pi 4A
- RetroPie / ES-X bajo X11

> Proyecto experimental y no oficial.  
> No todos los ports de PortMaster son compatibles con Debian.

## Funciones

- Instala la variante oficial **PortMaster Full**, incluyendo todos los runtimes distribuidos por upstream, para que no sea necesario instalarlos manualmente después.
- Configura X11 y las rutas SDL2 de Debian.
- Añade soporte multiarch ARMHF en ARM64.
- Compila `gptokeyb2` para x86_64.
- Corrige permisos y archivos creados como root.
- Aplica ajustes específicos para Debian.
- Corrige errores conocidos de `control.txt`.
- Conecta la configuración de mandos de ES-X con PortMaster cuando está disponible.
- Inicia la interfaz de PortMaster bajo X11 si RetroPie la abre desde una TTY y usa la resolución activa de X11.
- Ajusta la ventana de PortMaster al escritorio X11 en lugar de conservar la ventana de 640×480 del dispositivo genérico.

Estos ajustes se aplican a la interfaz de PortMaster; los juegos instalados conservan sus propios lanzadores. La compatibilidad de cada port y sus controles depende también del juego y de sus ejecutables.

## Instalación

```bash
cd ~
git clone https://github.com/Renetrox/PortMaster-RetroPie-Debian.git

cp ~/PortMaster-RetroPie-Debian/portmaster.sh \
   ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

chmod 644 ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

cd ~/RetroPie-Setup
sudo ./retropie_setup.sh
```

También puede instalarse directamente con:

```bash
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh portmaster
```

> La instalación utiliza `Install.Full.PortMaster.sh` de la versión oficial más reciente. Es una descarga considerablemente mayor que la instalación base porque incluye los runtimes de PortMaster; esto es intencional para dejar el entorno listo desde el primer uso.

## Limitaciones

PortMaster utiliza /dev/uinput para convertir las entradas del mando en
teclas mediante gptokeyb.

Cuando el kernel no incluye uinput, la interfaz de PortMaster puede funcionar,
pero algunos juegos deberán utilizar teclado o soporte de mando SDL nativo.

El kernel oficial probado en Orange Pi 4A no ofrece actualmente /dev/uinput.

## Ports probados

| Port | Plataforma | Estado |
| --- | --- | --- |
| Banana Duck | Debian x86_64 | Inicia |
| ROTA | Debian x86_64 | Inicia |
| PortMaster GUI | Debian x86_64 / ARM64 | En pruebas |
| Maldita Castilla | Debian ARM64 | En pruebas |

## Créditos

PortsMaster, PortMaster-GUI, RetroPie y gptokeyb / gptokeyb2.

Adaptación para Debian y RetroPie: Renetrox

## Licencia

MIT

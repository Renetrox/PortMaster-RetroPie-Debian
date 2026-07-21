# PortMaster para RetroPie en Debian

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

- Instala PortMaster dentro de RetroPie.
- Configura X11 y las rutas SDL2 de Debian.
- Añade soporte multiarch ARMHF en ARM64.
- Compila `gptokeyb2` para x86_64.
- Corrige permisos y archivos creados como root.
- Aplica ajustes específicos para Debian.
- Corrige errores conocidos de `control.txt`.

## Instalación

```bash
cd ~
git clone https://github.com/Renetrox/PortMaster-RetroPie-Debian.git

cp ~/PortMaster-RetroPie-Debian/portmaster.sh \
   ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

chmod 644 ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

cd ~/RetroPie-Setup
sudo ./retropie_setup.sh

También puede instalarse directamente con:

cd ~/RetroPie-Setup
sudo ./retropie_packages.sh portmaster
Limitaciones

PortMaster utiliza /dev/uinput para convertir las entradas del mando en
teclas mediante gptokeyb.

Cuando el kernel no incluye uinput, la interfaz de PortMaster puede funcionar,
pero algunos juegos deberán utilizar teclado o soporte de mando SDL nativo.

El kernel oficial probado en Orange Pi 4A no ofrece actualmente /dev/uinput.

Ports probados
Port	Plataforma	Estado
Banana Duck	Debian x86_64	Inicia
ROTA	Debian x86_64	Inicia
PortMaster GUI	Debian x86_64 / ARM64	En pruebas
Maldita Castilla	Debian ARM64	En pruebas
Créditos
PortsMaster
PortMaster-GUI
RetroPie
gptokeyb / gptokeyb2

Adaptación para Debian y RetroPie: Renetrox

Licencia

MIT

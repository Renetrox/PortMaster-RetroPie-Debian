# PortMaster para RetroPie en Debian

<img width="640" height="480" alt="Captura de pantalla_2026-07-21_17-28-53" src="https://github.com/user-attachments/assets/04568228-7d63-42d7-95fb-a32657fb7baf" />

Modulo experimental de RetroPie-Setup para instalar y adaptar [PortMaster](https://github.com/PortsMaster/PortMaster-GUI) en Debian.

Probado actualmente en:

- Debian 12 x86_64
- Debian 12 ARM64
- Orange Pi 4A
- RetroPie / ES-X bajo X11

> Proyecto experimental y no oficial.  
> No todos los ports de PortMaster son compatibles con Debian, pero hasta ahora muchos ports simples o bien empaquetados han funcionado directamente. Los casos mas dificiles suelen ser ports que requieren librerias de 32-bit o juegos complejos con motores como FNA/Mono, Godot, GameMaker, Unity o Wine.

## Estado del proyecto

Esta adaptacion busca hacer usable PortMaster en RetroPie sobre Debian/Armbian, fuera de los sistemas handheld para los que PortMaster fue pensado originalmente.

En las pruebas realizadas, la base funciona: PortMaster abre, descarga ports, respeta la estructura esperada por muchos launchers y varios juegos funcionan de una. Sin embargo, algunos ports necesitan ajustes adicionales porque Debian no siempre ofrece las mismas rutas, permisos, servicios o librerias que ArkOS, JELOS, AmberELEC, Batocera u otros sistemas soportados por PortMaster.

Los casos que mas suelen requerir adaptacion son:

- ports ARMHF/32-bit que necesitan librerias extra;
- juegos comerciales que dependen de una version exacta de los datos originales;
- launchers que esperan rutas o servicios especificos de handhelds;
- motores graficos pesados o sensibles a Mesa, SDL2, EGL, GLX, Panfrost o Panthor;
- ports que usan runtimes como Mono, FNA3D, GMloader, Godot, Unity, Wine, box86 o box64.

El objetivo no es prometer compatibilidad total con todo PortMaster, sino ofrecer una base funcional para RetroPie/Debian y documentar las recetas necesarias para ampliar compatibilidad.

## Funciones

- Instala la variante oficial **PortMaster Full**, incluyendo los runtimes distribuidos por upstream, para reducir instalaciones manuales posteriores.
- Configura X11 y las rutas SDL2 de Debian.
- Añade soporte multiarch ARMHF en ARM64 cuando el sistema lo permite.
- Compila o adapta `gptokeyb2` cuando el helper incluido no coincide con la arquitectura.
- Corrige permisos y archivos creados como root.
- Aplica ajustes especificos para Debian.
- Corrige errores conocidos de `control.txt`.
- Conecta la configuracion de mandos de ES-X con PortMaster cuando esta disponible.
- Inicia la interfaz de PortMaster bajo X11 si RetroPie la abre desde una TTY.
- Usa la resolucion activa de X11 y ajusta la ventana de PortMaster al escritorio.
- Prepara el entorno esperado por launchers que buscan `/roms/ports`.

Estos ajustes se aplican principalmente a la interfaz y al entorno base de PortMaster. Cada juego conserva su propio launcher, por lo que la compatibilidad final tambien depende del motor, los datos del juego y sus librerias.

## Instalacion

```bash
cd ~
git clone https://github.com/Renetrox/PortMaster-RetroPie-Debian.git

cp ~/PortMaster-RetroPie-Debian/portmaster.sh \
   ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

chmod 644 ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

cd ~/RetroPie-Setup
sudo ./retropie_setup.sh
```

Tambien puede instalarse directamente con:

```bash
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh portmaster
```

> La instalacion utiliza `Install.Full.PortMaster.sh` de la version oficial mas reciente. Es una descarga mayor que la instalacion base porque incluye los runtimes de PortMaster. Esto es intencional para dejar el entorno lo mas listo posible desde el primer uso.

## Compatibilidad observada

| Tipo de port | Estado esperado |
| --- | --- |
| SDL/OpenBOR/Doom engines simples | Alta probabilidad de funcionar |
| Godot simples | Generalmente viables, segun version y renderer |
| GameMaker/GMloader | Viables, pero pueden requerir librerias ARMHF |
| FNA/Mono | Viables, pero pueden requerir Mono, FNA3D, SDL2 y ajustes EGL/GLX |
| Unity/Wine/box86/box64 | Experimental y pesado |
| Ports comerciales complejos | Dependen de datos, version y parches exactos |

Hasta ahora, casi todo lo simple o bien empaquetado ha funcionado directamente. Los problemas mas frecuentes aparecieron en ports que necesitan librerias de 32-bit o en juegos complejos que requieren adaptacion por motor o por juego.

## Ports probados

| Port | Plataforma | Estado |
| --- | --- | --- |
| Banana Duck | Debian x86_64 | Inicia |
| ROTA | Debian x86_64 | Inicia |
| PortMaster GUI | Debian x86_64 / ARM64 | Funciona, en pruebas |
| Maldita Castilla | Debian ARM64 | Funciona con librerias ARMHF instaladas |
| Celeste64 | Debian ARM64 | Funciona |
| Abuse | Debian ARM64 | Funciona |
| Super Mario Bros Remastered | Debian ARM64 | Funciona con datos correctos |
| TMNT: Shredder's Revenge | Debian ARM64 | Parcial, requiere adaptacion grafica FNA/Mono/EGL |

## Limitaciones conocidas

PortMaster utiliza `/dev/uinput` para convertir entradas del mando en teclas mediante `gptokeyb`. Cuando el kernel no incluye `uinput`, la interfaz de PortMaster puede funcionar, pero algunos juegos deberan usar teclado o soporte de mando SDL nativo.

Otros problemas conocidos o probables:

- faltan librerias ARMHF/32-bit;
- el launcher espera `sudo` sin contrasena;
- el port intenta usar `/dev/tty0`, `oga_events` u otros servicios que no existen en Debian;
- `gptokeyb` no coincide con la arquitectura o no encuentra `uinput`;
- SDL/FNA intenta usar GLX cuando conviene EGL/GLES;
- Mesa cae en `llvmpipe/swrast` en vez de Panfrost/Panthor;
- el juego requiere una version especifica de datos de Steam/GOG;
- algunos ports pesados necesitan parches por juego.

El kernel oficial probado en Orange Pi 4A no siempre ofrece todas las opciones esperadas por los launchers de handhelds, por lo que algunos ajustes pueden depender del sistema instalado.

## Diagnostico recomendado

Cuando un port falla, revisar primero:

```bash
uname -m
cat /etc/os-release
ls -lh ~/RetroPie/roms/ports/PortMaster
ls -lh ~/RetroPie/roms/ports/<port>
tail -120 ~/RetroPie/roms/ports/<port>/log.txt
```

Para problemas graficos:

```bash
ls /usr/lib/aarch64-linux-gnu/dri | grep -E 'panfrost|panthor|swrast|kms'
glxinfo -B 2>/dev/null | grep -E 'direct rendering|OpenGL renderer|OpenGL vendor|OpenGL version'
eglinfo 2>/dev/null | grep -E 'EGL vendor|EGL version|driver|Device|MESA|panfrost|panthor|swrast|llvmpipe' | head -80
```

Para ports ARMHF/32-bit:

```bash
dpkg --print-foreign-architectures
ls /usr/lib/arm-linux-gnueabihf
file ~/RetroPie/roms/ports/<port>/<binary>
ldd ~/RetroPie/roms/ports/<port>/<binary>
```

## Nota sobre ports pesados

Juegos complejos pueden arrancar parcialmente y fallar recien al crear ventana, cargar FNA3D, abrir EGL/GLX, inicializar Mono o aplicar parches. Eso no significa necesariamente que el port sea imposible; significa que necesita una adaptacion especifica para Debian/ARM64.

## Creditos

PortsMaster, PortMaster-GUI, RetroPie y gptokeyb / gptokeyb2.

Adaptacion para Debian y RetroPie: Renetrox

## Licencia

MIT

---

# PortMaster for RetroPie on Debian

Experimental RetroPie-Setup module for installing and adapting [PortMaster](https://github.com/PortsMaster/PortMaster-GUI) on Debian.

Currently tested on:

- Debian 12 x86_64
- Debian 12 ARM64
- Orange Pi 4A
- RetroPie / ES-X under X11

> Experimental and unofficial project.  
> Not every PortMaster port is compatible with Debian, but many simple or well-packaged ports have worked directly so far. The hardest cases are usually ports that need 32-bit libraries or complex games using engines such as FNA/Mono, Godot, GameMaker, Unity, or Wine.

## Project status

This adaptation aims to make PortMaster usable in RetroPie on Debian/Armbian, outside the handheld operating systems PortMaster was originally designed for.

In testing, the base works: PortMaster opens, downloads ports, preserves the layout expected by many launchers, and several games work out of the box. However, some ports need extra adjustments because Debian does not always provide the same paths, permissions, services, or libraries as ArkOS, JELOS, AmberELEC, Batocera, or other PortMaster-supported systems.

The cases that most often need adaptation are:

- ARMHF/32-bit ports that need extra libraries;
- commercial games depending on an exact version of the original data;
- launchers expecting handheld-specific paths or services;
- graphics-heavy engines sensitive to Mesa, SDL2, EGL, GLX, Panfrost, or Panthor;
- ports using runtimes such as Mono, FNA3D, GMloader, Godot, Unity, Wine, box86, or box64.

The goal is not to promise full compatibility with every PortMaster port, but to provide a working base for RetroPie/Debian and document the recipes needed to expand compatibility.

## Features

- Installs the official **PortMaster Full** variant, including upstream runtimes, to reduce manual post-install steps.
- Configures X11 and Debian SDL2 paths.
- Adds ARMHF multiarch support on ARM64 when supported by the system.
- Builds or adapts `gptokeyb2` when the included helper does not match the host architecture.
- Fixes permissions and files created as root.
- Applies Debian-specific adjustments.
- Fixes known `control.txt` issues.
- Bridges ES-X controller configuration into PortMaster when available.
- Starts the PortMaster interface under X11 when RetroPie opens it from a TTY.
- Uses the active X11 resolution and fits the PortMaster window to the desktop.
- Prepares the layout expected by launchers that look for `/roms/ports`.

These fixes mainly apply to the PortMaster interface and base environment. Each game keeps its own launcher, so final compatibility also depends on the game engine, game data, and libraries.

## Installation

```bash
cd ~
git clone https://github.com/Renetrox/PortMaster-RetroPie-Debian.git

cp ~/PortMaster-RetroPie-Debian/portmaster.sh \
   ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

chmod 644 ~/RetroPie-Setup/scriptmodules/ports/portmaster.sh

cd ~/RetroPie-Setup
sudo ./retropie_setup.sh
```

It can also be installed directly with:

```bash
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh portmaster
```

> The installation uses `Install.Full.PortMaster.sh` from the latest official release. It is a larger download than the base install because it includes PortMaster runtimes. This is intentional, so the environment is as ready as possible from the first run.

## Observed compatibility

| Port type | Expected status |
| --- | --- |
| Simple SDL/OpenBOR/Doom engines | High chance of working |
| Simple Godot ports | Usually viable, depending on version and renderer |
| GameMaker/GMloader | Viable, but may require ARMHF libraries |
| FNA/Mono | Viable, but may require Mono, FNA3D, SDL2, and EGL/GLX adjustments |
| Unity/Wine/box86/box64 | Experimental and heavy |
| Complex commercial ports | Depend on exact data, version, and patches |

So far, almost everything simple or well-packaged has worked directly. The most common problems appeared in ports that need 32-bit libraries or in complex games that require per-engine or per-game adaptation.

## Tested ports

| Port | Platform | Status |
| --- | --- | --- |
| Banana Duck | Debian x86_64 | Starts |
| ROTA | Debian x86_64 | Starts |
| PortMaster GUI | Debian x86_64 / ARM64 | Works, still testing |
| Maldita Castilla | Debian ARM64 | Works with ARMHF libraries installed |
| Celeste64 | Debian ARM64 | Works |
| Abuse | Debian ARM64 | Works |
| Super Mario Bros Remastered | Debian ARM64 | Works with correct data |
| TMNT: Shredder's Revenge | Debian ARM64 | Partial, needs FNA/Mono/EGL graphics adaptation |

## Known limitations

PortMaster uses `/dev/uinput` to convert controller input into keyboard input through `gptokeyb`. When the kernel does not include `uinput`, the PortMaster interface may still work, but some games will need keyboard input or native SDL controller support.

Other known or likely issues:

- missing ARMHF/32-bit libraries;
- launchers expecting passwordless `sudo`;
- ports trying to use `/dev/tty0`, `oga_events`, or services not available on Debian;
- `gptokeyb` not matching the host architecture or not finding `uinput`;
- SDL/FNA trying to use GLX when EGL/GLES is preferable;
- Mesa falling back to `llvmpipe/swrast` instead of Panfrost/Panthor;
- games requiring a specific Steam/GOG data version;
- heavier ports needing per-game patches.

The official kernel tested on Orange Pi 4A does not always provide every option expected by handheld launchers, so some fixes may depend on the installed system.

## Recommended diagnostics

When a port fails, check first:

```bash
uname -m
cat /etc/os-release
ls -lh ~/RetroPie/roms/ports/PortMaster
ls -lh ~/RetroPie/roms/ports/<port>
tail -120 ~/RetroPie/roms/ports/<port>/log.txt
```

For graphics issues:

```bash
ls /usr/lib/aarch64-linux-gnu/dri | grep -E 'panfrost|panthor|swrast|kms'
glxinfo -B 2>/dev/null | grep -E 'direct rendering|OpenGL renderer|OpenGL vendor|OpenGL version'
eglinfo 2>/dev/null | grep -E 'EGL vendor|EGL version|driver|Device|MESA|panfrost|panthor|swrast|llvmpipe' | head -80
```

For ARMHF/32-bit ports:

```bash
dpkg --print-foreign-architectures
ls /usr/lib/arm-linux-gnueabihf
file ~/RetroPie/roms/ports/<port>/<binary>
ldd ~/RetroPie/roms/ports/<port>/<binary>
```

## Note about heavy ports

Complex games may partially start and only fail when creating a window, loading FNA3D, opening EGL/GLX, initializing Mono, or applying patches. That does not always mean the port is impossible; it means the port needs a Debian/ARM64-specific adaptation.

## Credits

PortsMaster, PortMaster-GUI, RetroPie, and gptokeyb / gptokeyb2.

Debian and RetroPie adaptation: Renetrox

## License

MIT

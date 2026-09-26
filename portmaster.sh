#!/usr/bin/env bash

# PortMaster integration for RetroPie-Setup
# Installs the official PortMaster release directly in RetroPie's Ports folder.

rp_module_id="portmaster"
rp_module_desc="PortMaster - Download and manage native Linux ports"
rp_module_help="Installs PortMaster in RetroPie's Ports directory, maps /roms/ports to the active RetroPie ports folder, bridges ES-X controller settings, and adapts the PortMaster GUI to X11 when RetroPie starts it from a TTY. On non-ARM64 systems it can build a native gptokeyb2 when the bundled helper is incompatible."
rp_module_licence="MIT https://github.com/PortsMaster/PortMaster-GUI/blob/main/LICENSE"
rp_module_section="exp"

PORTMASTER_INSTALLER_URL="https://github.com/PortsMaster/PortMaster-GUI/releases/latest/download/Install.PortMaster.sh"
GPTOKEYB2_REPO="https://github.com/PortsMaster/gptokeyb2.git"

function _update_hook_portmaster() {
    # Show manual/existing installations as installed in RetroPie-Setup.
    if [[ -d "$romdir/ports/PortMaster" && -f "$romdir/ports/PortMaster.sh" ]]; then
        mkdir -p "$md_inst"
    fi
}

function depends_portmaster() {
    getDepends \
        ca-certificates \
        curl \
        file \
        unzip \
        jq \
        squashfs-tools \
        python3

    # PortMaster's SDL GUI needs an X11 session on desktop RetroPie/Debian.
    # xrandr is also used to pass the real X11 size to pugwash.
    getDepends \
        xinit \
        x11-xserver-utils

    # PortMaster currently supplies an appropriate helper on ARM64. Desktop
    # x86/x64 and other architectures may require a native local build.
    case "$(uname -m)" in
        aarch64|arm64)
            ;;
        *)
            getDepends \
                git \
                cmake \
                build-essential \
                pkg-config \
                patchelf \
                libsdl2-dev \
                libevdev-dev
            ;;
    esac
}

function _prepare_es_input_bridge_portmaster() {
    local target_dir="$home/.config/emulationstation"
    local target="$target_dir/es_input.cfg"
    local source=""

    if [[ -f "$home/.emulationstation/es_input.cfg" ]]; then
        source="$home/.emulationstation/es_input.cfg"
    elif [[ -f "/opt/retropie/configs/all/emulationstation/es_input.cfg" ]]; then
        source="/opt/retropie/configs/all/emulationstation/es_input.cfg"
    else
        # PortMaster will retain its bundled SDL database until ES creates a
        # controller configuration. This is not fatal during installation.
        return 0
    fi

    mkdir -p "$target_dir" "$md_inst"

    if [[ -e "$target" && ! -L "$target" ]]; then
        if ! _same_directory_portmaster "$target" "$source"; then
            md_ret_errors+=(
                "$target already exists and was preserved. PortMaster may not use ES-X's controller mapping."
            )
            return 0
        fi
        return 0
    fi

    ln -sfn "$source" "$target"
    printf '%s\n' "$source" > "$md_inst/es-input-bridge-source"
}

function _patch_x11_gui_launcher_portmaster() {
    local launcher="$romdir/ports/PortMaster.sh"
    local tmp=""

    [[ -f "$launcher" ]] || return 1

    # This patch is intentionally limited to PortMaster's GUI launcher. Ports
    # downloaded by PortMaster keep their original display handling.
    if ! grep -q '^# RETROPIE_PORTMASTER_X11_START$' "$launcher"; then
        tmp="$(mktemp)" || return 1
        awk '
            {
                print
                if (!done && $0 ~ /^export XDG_DATA_HOME=/) {
                    print ""
                    print "# RETROPIE_PORTMASTER_X11_START"
                    print "# Desktop RetroPie may launch Ports from a TTY. Re-enter this"
                    print "# launcher as the client of a temporary X server when needed."
                    print "if ! xrandr --current >/dev/null 2>&1; then"
                    print "  if command -v startx >/dev/null 2>&1; then"
                    print "    export PM_RETROPIE_STARTED_X=1"
                    print "    exec startx \"$0\" -- :1"
                    print "  fi"
                    print "fi"
                    print "# RETROPIE_PORTMASTER_X11_START_END"
                    done=1
                }
            }
        ' "$launcher" > "$tmp" && cat "$tmp" > "$launcher"
        rm -f "$tmp"
    fi

    if ! grep -q '^    export PM_RETROPIE_STARTED_X=1$' "$launcher"; then
        sed -i '/^    exec startx "\$0" -- :1$/i\    export PM_RETROPIE_STARTED_X=1' "$launcher"
    fi

    # Keep the X11 backend local to PortMaster's own GUI.  The Debian modular
    # file is also sourced by installed games, so forcing SDL_VIDEODRIVER there
    # prevents SDL/KMS games from starting directly from a TTY.
    if ! grep -q '^# RETROPIE_PORTMASTER_X11_ENV$' "$launcher"; then
        tmp="$(mktemp)" || return 1
        awk '
            {
                print
                if (!done && $0 ~ /^# RETROPIE_PORTMASTER_X11_START_END$/) {
                    print ""
                    print "# RETROPIE_PORTMASTER_X11_ENV"
                    print "if xrandr --current >/dev/null 2>&1; then"
                    print "  export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\""
                    print "  export SDL_VIDEODRIVER=x11"
                    print "fi"
                    print "# RETROPIE_PORTMASTER_X11_ENV_END"
                    done=1
                }
            }
            END {
                if (!done) exit 1
            }
        ' "$launcher" > "$tmp" && cat "$tmp" > "$launcher"
        local patch_ret=$?
        rm -f "$tmp"
        [[ "$patch_ret" -eq 0 ]] || return "$patch_ret"
    fi

    # Migrate the previous patch, which ran after get_controls.
    sed -i '/^# RETROPIE_PORTMASTER_X11_SIZE$/,/^# RETROPIE_PORTMASTER_X11_SIZE_END$/d' "$launcher"
    if ! grep -q '^# RETROPIE_PORTMASTER_X11_SIZE$' "$launcher"; then
        tmp="$(mktemp)" || return 1
        awk '
            {
                print
                if (!done && $0 ~ /^source \$controlfolder\/control\.txt$/) {
                    print ""
                    print "# RETROPIE_PORTMASTER_X11_SIZE"
                    print "# Select the preferred X11 mode before PortMaster detects the display."
                    print "if [[ \"${PM_RETROPIE_STARTED_X:-}\" == 1 ]]; then"
                    print "  xrandr --auto >/dev/null 2>&1 || true"
                    print "fi"
                    print "PM_X11_RESOLUTION=\"$(xrandr --current 2>/dev/null | awk '\''/\\*/ {print $1; exit}'\'')\""
                    print "if [[ \"$PM_X11_RESOLUTION\" =~ ^([0-9]+)x([0-9]+)$ ]]; then"
                    print "  export DISPLAY_WIDTH=\"${BASH_REMATCH[1]}\""
                    print "  export DISPLAY_HEIGHT=\"${BASH_REMATCH[2]}\""
                    print "  export PM_RETROPIE_X11_RESOLUTION=\"$PM_X11_RESOLUTION\""
                    print "  export PM_RETROPIE_X11=1"
                    print "fi"
                    print "unset PM_X11_RESOLUTION"
                    print "# RETROPIE_PORTMASTER_X11_SIZE_END"
                    done=1
                }
            }
        ' "$launcher" > "$tmp" && cat "$tmp" > "$launcher"
        rm -f "$tmp"
    fi

    # Migrate launchers patched by the previous module revision.
    if ! grep -q '^  export PM_RETROPIE_X11=1$' "$launcher"; then
        sed -i '/^  export PM_RETROPIE_X11_RESOLUTION=/a\  export PM_RETROPIE_X11=1' "$launcher"
    fi

    chmod 755 "$launcher"
}

function _patch_pugwash_x11_portmaster() {
    local pugwash="$romdir/ports/PortMaster/pugwash"
    [[ -f "$pugwash" ]] || return 1

    python3 - "$pugwash" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
marker = '        # RETROPIE_PORTMASTER_X11_RESOLUTION\n'
if marker not in source:
    anchor = '        # Create the window\n'
    if source.count(anchor) != 1:
        raise SystemExit('PortMaster GUI window anchor not found')
    block = '''        # RETROPIE_PORTMASTER_X11_RESOLUTION
        # Use the active X11 mode on desktop RetroPie/Debian.
        import os as _pm_os
        import re as _pm_re
        _pm_mode = _pm_os.environ.get("PM_RETROPIE_X11_RESOLUTION", "")
        _pm_match = _pm_re.fullmatch(r"([0-9]+)x([0-9]+)", _pm_mode)
        if _pm_match:
            capabilities = harbourmaster.device_info(
                override_resolution=tuple(map(int, _pm_match.groups())))

'''
    source = source.replace(anchor, block + anchor, 1)

old = '            window_flags = sdl2.SDL_WINDOW_FULLSCREEN\n'
old_desktop = '            window_flags = sdl2.SDL_WINDOW_FULLSCREEN_DESKTOP\n'
new = '''            # RETROPIE_PORTMASTER_X11_FULLSCREEN
            if _pm_os.environ.get("PM_RETROPIE_X11") == "1":
                window_flags = sdl2.SDL_WINDOW_FULLSCREEN_DESKTOP
            else:
                window_flags = sdl2.SDL_WINDOW_FULLSCREEN
'''
if 'RETROPIE_PORTMASTER_X11_FULLSCREEN' not in source:
    if old in source:
        source = source.replace(old, new, 1)
    elif old_desktop in source:
        source = source.replace(old_desktop, new, 1)
    else:
        raise SystemExit('PortMaster GUI fullscreen anchor not found')

path.write_text(source)
PY
}

function _same_directory_portmaster() {
    local first="$1"
    local second="$2"

    [[ -e "$first" && -e "$second" ]] || return 1
    [[ "$(stat -Lc '%d:%i' "$first")" == "$(stat -Lc '%d:%i' "$second")" ]]
}

function _prepare_roms_link_portmaster() {
    local ports_dir="$romdir/ports"
    local link_path="/roms/ports"

    mkRomDir "ports"
    mkdir -p /roms "$md_inst"

    if [[ -e "$link_path" || -L "$link_path" ]]; then
        if _same_directory_portmaster "$link_path" "$ports_dir"; then
            return 0
        fi

        md_ret_errors+=(
            "$link_path already exists and does not point to $ports_dir. It was not modified."
        )
        return 1
    fi

    ln -s "$ports_dir" "$link_path" || return 1
    touch "$md_inst/created-roms-ports-link"
}

function _gptokeyb_matches_host_portmaster() {
    local binary="$1"
    local machine
    local description

    [[ -f "$binary" ]] || return 1

    machine="$(uname -m)"
    description="$(LC_ALL=C file -b "$binary")"

    case "$machine" in
        x86_64|amd64)
            [[ "$description" == *"x86-64"* ]]
            ;;
        aarch64|arm64)
            [[ "$description" == *"ARM aarch64"* ]]
            ;;
        armv6l|armv7l|armv8l)
            [[ "$description" == *"ARM"* && "$description" != *"aarch64"* ]]
            ;;
        i386|i486|i586|i686)
            [[ "$description" == *"Intel 80386"* ]]
            ;;
        *)
            return 1
            ;;
    esac
}

function _native_arch_portmaster() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        i386|i486|i586|i686) echo "x86" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv6l|armv7l|armv8l) echo "armhf" ;;
        *) return 1 ;;
    esac
}

function _install_native_gptokeyb2_portmaster() {
    local pm_dir="$romdir/ports/PortMaster"
    local native_binary="$md_inst/gptokeyb2.native"
    local native_arch
    local native_library

    native_arch="$(_native_arch_portmaster)" || return 1
    native_library="$md_inst/libinterpose.${native_arch}.so"

    [[ -x "$native_binary" && -f "$native_library" ]] || return 1

    if [[ -e "$pm_dir/gptokeyb" && ! -e "$pm_dir/gptokeyb.upstream.bak" ]]; then
        cp -a "$pm_dir/gptokeyb" "$pm_dir/gptokeyb.upstream.bak"
    fi
    if [[ -e "$pm_dir/gptokeyb2" && ! -e "$pm_dir/gptokeyb2.upstream.bak" ]]; then
        cp -a "$pm_dir/gptokeyb2" "$pm_dir/gptokeyb2.upstream.bak"
    fi

    install -m 755 "$native_binary" "$pm_dir/gptokeyb2"
    install -m 755 "$native_library" "$pm_dir/libinterpose.${native_arch}.so"

    # Some older ports invoke GPTOKEYB rather than GPTOKEYB2. Provide a
    # wrapper that preloads the interpose library required by gptokeyb2.
    rm -f "$pm_dir/gptokeyb"
    cat > "$pm_dir/gptokeyb" <<EOF
#!/usr/bin/env bash
controlfolder="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec env LD_PRELOAD="\$controlfolder/libinterpose.${native_arch}.so" \
    "\$controlfolder/gptokeyb2" "\$@"
EOF
    chmod 755 "$pm_dir/gptokeyb"
}

function _build_native_gptokeyb2_portmaster() {
    local source_dir="$md_build/gptokeyb2"
    local build_dir="$source_dir/build-retropie"
    local native_binary="$build_dir/gptokeyb2"
    local build_library="$build_dir/lib/libinterpose.so"
    local native_arch
    local native_library

    native_arch="$(_native_arch_portmaster)" || return 1
    native_library="libinterpose.${native_arch}.so"

    printMsgs "console" "Building a native gptokeyb2 for $(uname -m) ..."

    rm -rf "$source_dir"
    mkdir -p "$md_build" "$md_inst"

    gitPullOrClone "$source_dir" "$GPTOKEYB2_REPO" "master" "" 1 || return 1

    cmake \
        -S "$source_dir" \
        -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release || return 1

    cmake --build "$build_dir" -j"$(nproc)" || return 1

    if [[ ! -f "$native_binary" || ! -f "$build_library" ]]; then
        md_ret_errors+=("gptokeyb2 compiled, but its binary or libinterpose.so was not found.")
        return 1
    fi

    # Match PortMaster's official packaging: give the interpose library an
    # architecture-specific SONAME and make gptokeyb2 depend on that name.
    patchelf --replace-needed libinterpose.so "$native_library" "$native_binary" || return 1
    patchelf --set-soname "$native_library" "$build_library" || return 1

    strip "$native_binary" 2>/dev/null || true
    strip "$build_library" 2>/dev/null || true

    install -m 755 "$native_binary" "$md_inst/gptokeyb2.native"
    install -m 755 "$build_library" "$md_inst/$native_library"

    _install_native_gptokeyb2_portmaster
}


function _install_debian_mod_portmaster() {
    local pm_dir="$romdir/ports/PortMaster"
    local mod_dir="$pm_dir/mod_Debian GNU"
    local mod_file="$mod_dir/Linux.txt"

    mkdir -p "$mod_dir"

    cat > "$mod_file" <<'EOF'
#!/bin/bash
#
# SPDX-License-Identifier: MIT
#

## Modular - Debian GNU/Linux
#
# PortMaster builds the modular filename from CFW_NAME. Debian reports
# "Debian GNU/Linux", so this file is intentionally stored as:
#   mod_Debian GNU/Linux.txt

# Do not override ESUDO here. Individual ports may legitimately need it for
# uinput or other device permissions. The PortMaster GUI launcher itself is
# patched below so that pugwash still runs as the desktop user.

# Runtime directory used by SDL/audio helpers. Do not select a video backend
# here: this modular file is also sourced by every installed PortMaster game.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Let PySDL2 find the native SDL libraries on Debian multiarch systems.
case "$(uname -m)" in
    aarch64|arm64)
        export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib/aarch64-linux-gnu}"
        ;;
    x86_64|amd64)
        export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib/x86_64-linux-gnu}"
        ;;
    armv6l|armv7l|armv8l)
        export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib/arm-linux-gnueabihf}"
        ;;
    i386|i486|i586|i686)
        export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib/i386-linux-gnu}"
        ;;
    *)
        export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib}"
        ;;
esac

# ARMHF ports running on an ARM64 Debian host.
if [[ "${PORT_32BIT:-N}" == "Y" ]]; then
    if [[ -d /usr/lib/arm-linux-gnueabihf ]]; then
        export LD_LIBRARY_PATH="/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf:${LD_LIBRARY_PATH:-}"
    fi
fi

# Common GameMaker/Godot options used by PortMaster launchers.
GODOT2_OPTS="-r ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f"
GODOT_OPTS="--resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f"

pm_platform_helper() {
    if [[ -e "${PM_PIPE:-}" ]]; then
        PortMasterDialogExit
    fi

    printf ""
}
EOF

    chmod 644 "$mod_file"
}


function _normalize_launcher_name_portmaster() {
    local ports_dir="$romdir/ports"
    local official_launcher="$ports_dir/PortMaster.sh"
    local alternate_launcher=""

    [[ -f "$official_launcher" ]] && return 0

    alternate_launcher="$(
        find "$ports_dir" -maxdepth 1 -type f -iname 'portmaster.sh' \
            ! -path "$official_launcher" -print -quit 2>/dev/null
    )"

    if [[ -n "$alternate_launcher" ]]; then
        mv -f "$alternate_launcher" "$official_launcher"
    fi

    [[ -f "$official_launcher" ]]
}

function _fix_portmaster_install_portmaster() {
    _normalize_launcher_name_portmaster || true

    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local official_launcher="$ports_dir/PortMaster.sh"
    local control_file="$pm_dir/control.txt"
    local device_info_file="$pm_dir/device_info.txt"
    local pmsplash_file="$pm_dir/utils/pmsplash.txt"

    _install_debian_mod_portmaster
    _patch_x11_gui_launcher_portmaster || return 1
    _patch_pugwash_x11_portmaster || return 1

    # Avoid "binary operator expected" when ESUDO contains several words.
    # Also guard the optional ArkOS file before trying to read it.
    if [[ -f "$control_file" ]]; then
        sed -i \
            -e 's~\[ -z \$ESUDO \]~[ -z "$ESUDO" ]~' \
            -e 's~\[ -f "/boot/rk3326-rg351v-linux.dtb" \] || \[ $(cat "/storage/.config/.OS_ARCH") == "RG351V" \]~[ -f "/boot/rk3326-rg351v-linux.dtb" ] || { [ -f "/storage/.config/.OS_ARCH" ] \&\& [ "$(cat "/storage/.config/.OS_ARCH")" = "RG351V" ]; }~' \
            -e 's~^[[:space:]]*\$ESUDO chmod 666 /dev/uinput[[:space:]]*$~  [ -e /dev/uinput ] \&\& $ESUDO chmod 666 /dev/uinput~' \
            "$control_file"

        # A locally built helper replaces the architecture-specific upstream
        # gptokeyb. Route both variables through gptokeyb2 with LD_PRELOAD.
        if [[ -x "$md_inst/gptokeyb2.native" ]]; then
            sed -i \
                -e 's|^export GPTOKEYB2=.*$|export GPTOKEYB2="$ESUDO env LD_PRELOAD=$controlfolder/libinterpose.${DEVICE_ARCH}.so $controlfolder/gptokeyb2 $ESUDOKILL2"|' \
                -e 's|^export GPTOKEYB=.*$|export GPTOKEYB="$ESUDO env LD_PRELOAD=$controlfolder/libinterpose.${DEVICE_ARCH}.so $controlfolder/gptokeyb2 $ESUDOKILL2"|' \
                "$control_file"
        fi
    fi

    # Debian's CFW name contains a slash. Sanitize only the diagnostic dump
    # filename so it cannot accidentally become a nonexistent directory.
    if [[ -f "$device_info_file" ]]; then
        sed -i \
            's~cat << __INFO_DUMP__ | tee "$HOME/device_info_${CFW_NAME}_${DEVICE_NAME}.txt"~DEVICE_INFO_FILE="$(printf "%s_%s" "$CFW_NAME" "$DEVICE_NAME" | tr "/[:space:]" "__")"\ncat << __INFO_DUMP__ | tee "$HOME/device_info_${DEVICE_INFO_FILE}.txt"~' \
            "$device_info_file"
    fi

    # Keep the PortMaster GUI in the desktop user's X11 session. Do not run
    # pugwash as root, and manage its reboot marker as the owning user.
    #
    # PortMaster intentionally ships some helpers (notably gptokeyb and
    # gptokeyb2) without an executable bit and fixes them from this launcher.
    # Preserve that behaviour, but perform it as the owning desktop user.
    if [[ -f "$official_launcher" ]]; then
        sed -i \
            -e 's|^export PYSDL2_DLL_PATH="/usr/lib"$|export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib}"|' \
            -e 's|^\([[:space:]]*\)\$ESUDO \.\/pugwash \$PORTMASTER_CMDS|\1./pugwash $PORTMASTER_CMDS|' \
            -e 's|^\([[:space:]]*\)\$ESUDO rm -f "${controlfolder}/.pugwash-reboot"|\1rm -f "${controlfolder}/.pugwash-reboot"|' \
            -e 's|^\$ESUDO chmod -R +x \.$|chmod -R a+x .|' \
            -e 's|^: # permissions handled by RetroPie-Setup$|chmod -R a+x .|' \
            -e 's|^[[:space:]]*chmod -R u+rwX,go+rX \.[[:space:]]*$|chmod -R a+x .|' \
            -e 's|^[[:space:]]*chmod -R u+rwX,go+rX "\$controlfolder"[[:space:]]*$|chmod -R a+x "$controlfolder"|' \
            "$official_launcher"
    fi

    # The splash stop marker is user-owned on Debian, so remove it directly
    # instead of starting a root-owned GUI state.
    if [[ -f "$pmsplash_file" ]]; then
        sed -i \
            's|^\[ -f "$PMSPLASH_STOP" \] && \$ESUDO rm -f "$PMSPLASH_STOP"$|[ -f "$PMSPLASH_STOP" ] \&\& rm -f "$PMSPLASH_STOP"|' \
            "$pmsplash_file"
    fi

    # Determine the desktop account that owns RetroPie's Ports directory.
    # Normally RetroPie-Setup supplies __user/__group. The stat fallback also
    # covers modules launched from an already-root shell.
    local target_user="${__user:-${user:-}}"
    local target_group="${__group:-}"

    if [[ -z "$target_user" || "$target_user" == "root" ]]; then
        target_user="$(stat -Lc '%U' "$ports_dir" 2>/dev/null || true)"
    fi

    if [[ -n "$target_user" && "$target_user" != "root" ]]; then
        [[ -n "$target_group" && "$target_group" != "root" ]] ||
            target_group="$(id -gn "$target_user")"

        # Ownership must be corrected before the desktop launcher runs.
        chown -R "$target_user:$target_group" "$pm_dir"
        chown "$target_user:$target_group" \
            "$ports_dir/Install.PortMaster.sh" \
            "$official_launcher" 2>/dev/null || true
    fi

    # Remove stale state and apply permissions during configuration. The
    # executable pass is required even before PortMaster's GUI is opened:
    # installed ports can call gptokeyb directly from their own launchers.
    rm -f "$pm_dir/.pugwash-reboot"
    chmod -R u+rwX,go+rX "$pm_dir"
    chmod -R a+x "$pm_dir"
    chmod 755 "$official_launcher" 2>/dev/null || true
}

function install_bin_portmaster() {
    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local installer="$ports_dir/Install.PortMaster.sh"
    local official_launcher="$ports_dir/PortMaster.sh"

    _prepare_roms_link_portmaster || return 1
    _prepare_es_input_bridge_portmaster || return 1

    download "$PORTMASTER_INSTALLER_URL" "$installer" || return 1
    chmod +x "$installer"

    # The official installer expects to operate from the Ports directory.
    pushd "$ports_dir" >/dev/null || return 1
    env \
        HOME="$home" \
        USER="$__user" \
        LOGNAME="$__user" \
        SUDO_USER="$__user" \
        XDG_DATA_HOME="$home/.local/share" \
        bash "$installer"
    local ret=$?
    popd >/dev/null || true
    [[ "$ret" -eq 0 ]] || return "$ret"

    _normalize_launcher_name_portmaster || true

    # PortMaster's actual installed layout has the launcher at the root of
    # roms/ports and its data/control files inside roms/ports/PortMaster.
    if [[ ! -f "$official_launcher" || ! -f "$pm_dir/control.txt" ]]; then
        md_ret_errors+=(
            "The official installer finished, but PortMaster was not found in $ports_dir."
        )
        return 1
    fi

    if ! _gptokeyb_matches_host_portmaster "$pm_dir/gptokeyb2"; then
        case "$(uname -m)" in
            aarch64|arm64)
                md_ret_errors+=(
                    "The bundled gptokeyb2 is not compatible with this ARM64 system."
                )
                return 1
                ;;
            *)
                _build_native_gptokeyb2_portmaster || return 1
                ;;
        esac
    elif [[ -x "$md_inst/gptokeyb2.native" ]]; then
        # Reapply a previously compiled helper after a PortMaster reinstall.
        # Older module versions stored only the executable, so rebuild when
        # the matching interpose library is missing.
        if ! _install_native_gptokeyb2_portmaster; then
            _build_native_gptokeyb2_portmaster || return 1
        fi
    fi

    _fix_portmaster_install_portmaster
    mkdir -p "$md_inst"
}

function configure_portmaster() {
    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local official_launcher="$ports_dir/PortMaster.sh"

    [[ "$md_mode" == "remove" ]] && return

    _normalize_launcher_name_portmaster || true

    if [[ ! -f "$official_launcher" || ! -f "$pm_dir/control.txt" ]]; then
        md_ret_errors+=("PortMaster is not installed correctly in $ports_dir.")
        return 1
    fi

    _prepare_es_input_bridge_portmaster || return 1

    # Do not call addPort here: it would overwrite PortMaster's own launcher.
    # The Ports system already executes every .sh using `bash %ROM%`.
    chmod +x "$official_launcher"
    addSystem "ports"

    if [[ -x "$md_inst/gptokeyb2.native" ]]; then
        if ! _install_native_gptokeyb2_portmaster; then
            case "$(uname -m)" in
                aarch64|arm64)
                    md_ret_errors+=("The saved native gptokeyb2 support files are incomplete.")
                    return 1
                    ;;
                *)
                    _build_native_gptokeyb2_portmaster || return 1
                    ;;
            esac
        fi
    fi

    _fix_portmaster_install_portmaster
}

function remove_portmaster() {
    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local remove_link=0

    [[ -f "$md_inst/created-roms-ports-link" ]] && remove_link=1

    # Remove only the ES input symlink created by this module. Never remove a
    # real configuration file or a link subsequently changed by the user.
    if [[ -f "$md_inst/es-input-bridge-source" ]]; then
        local es_input_source
        es_input_source="$(< "$md_inst/es-input-bridge-source")"
        if [[ -L "$home/.config/emulationstation/es_input.cfg" ]] &&
           [[ "$(readlink "$home/.config/emulationstation/es_input.cfg")" == "$es_input_source" ]]; then
            rm -f "$home/.config/emulationstation/es_input.cfg"
            rmdir "$home/.config/emulationstation" 2>/dev/null || true
        fi
    fi

    # Remove PortMaster itself while preserving every installed game/port.
    rm -rf "$pm_dir"
    rm -f \
        "$ports_dir/Install.PortMaster.sh" \
        "$ports_dir/PortMaster.sh"

    if [[ "$remove_link" -eq 1 && -L /roms/ports ]]; then
        if _same_directory_portmaster /roms/ports "$ports_dir"; then
            rm -f /roms/ports
            rmdir /roms 2>/dev/null || true
        fi
    fi

    # Remove the Ports system only when no other port launchers remain.
    if [[ "$(find "$ports_dir" -maxdepth 1 -type f -name '*.sh' | wc -l)" -eq 0 ]]; then
        delSystem "ports"
    fi

    rm -rf "$md_inst"
}

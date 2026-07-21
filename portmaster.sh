#!/usr/bin/env bash

# PortMaster integration for RetroPie-Setup
# Installs the official PortMaster release directly in RetroPie's Ports folder.

rp_module_id="portmaster"
rp_module_desc="PortMaster - Download and manage native Linux ports"
rp_module_help="Installs PortMaster in RetroPie's Ports directory and maps /roms/ports to the active RetroPie ports folder. On non-ARM64 systems it can build a native gptokeyb2 when the bundled helper is incompatible."
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

# X11 desktop session used by RetroPie/ES-X.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0.0}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"

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

function _fix_portmaster_install_portmaster() {
    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local official_launcher="$ports_dir/PortMaster.sh"
    local control_file="$pm_dir/control.txt"
    local device_info_file="$pm_dir/device_info.txt"
    local pmsplash_file="$pm_dir/utils/pmsplash.txt"

    _install_debian_mod_portmaster

    # Avoid "binary operator expected" when ESUDO contains several words.
    # Also guard the optional ArkOS file before trying to read it.
    if [[ -f "$control_file" ]]; then
        sed -i \
            -e 's~\[ -z \$ESUDO \]~[ -z "$ESUDO" ]~' \
            -e 's~\[ -f "/boot/rk3326-rg351v-linux.dtb" \] || \[ $(cat "/storage/.config/.OS_ARCH") == "RG351V" \]~[ -f "/boot/rk3326-rg351v-linux.dtb" ] || { [ -f "/storage/.config/.OS_ARCH" ] \&\& [ "$(cat "/storage/.config/.OS_ARCH")" = "RG351V" ]; }~' \
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
    if [[ -f "$official_launcher" ]]; then
        sed -i \
            -e 's|^export PYSDL2_DLL_PATH="/usr/lib"$|export PYSDL2_DLL_PATH="${PYSDL2_DLL_PATH:-/usr/lib}"|' \
            -e 's|^\([[:space:]]*\)\$ESUDO \.\/pugwash \$PORTMASTER_CMDS|\1./pugwash $PORTMASTER_CMDS|' \
            -e 's|^\([[:space:]]*\)\$ESUDO rm -f "${controlfolder}/.pugwash-reboot"|\1rm -f "${controlfolder}/.pugwash-reboot"|' \
            -e 's|^\$ESUDO chmod -R +x \.$|chmod -R u+rwX,go+rX .|' \
            "$official_launcher"
    fi

    # The splash stop marker is user-owned on Debian, so remove it directly
    # instead of starting a root-owned GUI state.
    if [[ -f "$pmsplash_file" ]]; then
        sed -i \
            's|^\[ -f "$PMSPLASH_STOP" \] && \$ESUDO rm -f "$PMSPLASH_STOP"$|[ -f "$PMSPLASH_STOP" ] \&\& rm -f "$PMSPLASH_STOP"|' \
            "$pmsplash_file"
    fi

    # Remove a stale update marker possibly created during an earlier
    # root-owned first launch.
    rm -f "$pm_dir/.pugwash-reboot"

    chmod 755 "$official_launcher" 2>/dev/null || true
    chmod -R u+rwX,go+rX "$pm_dir"

    # RetroPie-Setup runs as root, while EmulationStation runs as the selected
    # account. Keep both PortMaster and its writable configuration user-owned.
    if [[ "$__user" != "root" ]]; then
        chown -R "$__user:$__group" "$pm_dir"
        chown "$__user:$__group" \
            "$ports_dir/Install.PortMaster.sh" \
            "$official_launcher" 2>/dev/null || true
    fi
}

function install_bin_portmaster() {
    local ports_dir="$romdir/ports"
    local pm_dir="$ports_dir/PortMaster"
    local installer="$ports_dir/Install.PortMaster.sh"
    local official_launcher="$ports_dir/PortMaster.sh"

    _prepare_roms_link_portmaster || return 1

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

    if [[ ! -f "$official_launcher" || ! -f "$pm_dir/control.txt" ]]; then
        md_ret_errors+=("PortMaster is not installed correctly in $ports_dir.")
        return 1
    fi

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

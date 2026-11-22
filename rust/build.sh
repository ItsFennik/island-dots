#!/usr/bin/env bash
# Build the Rust Spotlight and Settings binaries and install them for Island.
# The Fedora gtk4-layer-shell runtime package ships the library without the -devel
# pkg-config file, so this creates a user-local shim when the real one is missing.

set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
local_lib="$HOME/.local/lib"
local_pc="$local_lib/pkgconfig"

if ! pkg-config --exists gtk4-layer-shell-0 2>/dev/null; then
    lib=$(ldconfig -p 2>/dev/null | awk '/libgtk4-layer-shell[.]so[.]0 / {print $NF}' | tail -n1)
    if [ -z "$lib" ]; then
        printf 'build.sh: libgtk4-layer-shell.so.0 not found\n' >&2
        exit 1
    fi
    mkdir -p "$local_pc" "$local_lib"
    ln -sf "$lib" "$local_lib/libgtk4-layer-shell.so"
    cat > "$local_pc/gtk4-layer-shell-0.pc" <<EOF
prefix=$HOME/.local
libdir=$local_lib
includedir=/usr/include

Name: gtk4-layer-shell
Description: Wayland layer-shell support for GTK4 (runtime library)
Version: 1.3.0
Libs: -L\${libdir} -lgtk4-layer-shell
Cflags: -I\${includedir}
EOF
fi

export PATH="$HOME/.cargo/bin:$PATH"
export PKG_CONFIG_PATH="$local_pc${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

cargo build --release --bins --manifest-path "$root/Cargo.toml"

install -d "$HOME/.local/bin"
install -m 755 "$root/target/release/island-spotlight" "$HOME/.local/bin/island-spotlight"
install -m 755 "$root/target/release/island-settings" "$HOME/.local/bin/island-settings"

printf 'installed %s and %s\n' "$HOME/.local/bin/island-spotlight" "$HOME/.local/bin/island-settings"

#!/usr/bin/env bash
# envkey installer / uninstaller — portable across machines.
# Installs the envkey binary + per-shell collect snippets to standard
# locations and wires the detected shells' startup files (idempotent).
#
#   ./install.sh             install (idempotent)
#   ./install.sh --dry-run   preview without changes
#   ./install.sh --uninstall remove files + wiring (keychain entries kept)
#
# Secret VALUES never travel with migration; on a fresh machine you re-enter
# them with: envkey set NAME <value>   (values live only in macOS Keychain).

set -u

BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/envkey"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="### envkey (managed installer) ###"
STAMP_END="### end envkey ###"

dry_run=0
mode="install"
MODE_BIN=""
MODE_SHARE=""
declare -a HOOKS=()

info() { printf '[\033[1;34menvkey\033[0m] %s\n' "$*"; }
warn() { printf '[\033[1;33menvkey\033[0m] %s\n' "$*" >&2; }

for a in "$@"; do
    case "$a" in
        --dry-run) dry_run=1; MODE_BIN=" (dry)"; MODE_SHARE=" (dry)";;
        --uninstall) mode="uninstall";;
        *) warn "ignored unknown arg: $a";;
    esac
done

# --- detect installed shells (by command or startup file presence) ---
[[ -x "$(command -v bash)"   || -f "$HOME/.bash_profile" || -f "$HOME/.bashrc" ]] && HOOKS+=(bash)
[[ -x "$(command -v zsh)"    || -f "$HOME/.zshrc" ]] && HOOKS+=(zsh)
[[ -x "$(command -v fish)"   || -d "$HOME/.config/fish" ]] && HOOKS+=(fish)

startup_file() {
    local sh="$1"
    case "$sh" in
        bash)
            if [[ -f "$HOME/.bash_profile" ]]; then echo "$HOME/.bash_profile";
            else echo "$HOME/.bashrc"; fi ;;
        zsh)  echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
    esac
}

wired() { [[ -f "$1" ]] && grep -qF "$STAMP" "$1"; }

uninstall() {
    info "uninstall mode"
    for sh in "${HOOKS[@]}"; do
        local f; f="$(startup_file "$sh")"
        if [[ -f "$f" ]] && wired "$f"; then
            info "removing wiring from $f"
            [[ $dry_run -eq 0 ]] && perl -0pi -e "s/\n*${STAMP}.*?${STAMP_END}\n*//s" "$f"
        fi
    done
    info "removing $BIN_DIR/envkey$MODE_BIN"
    [[ $dry_run -eq 0 ]] && rm -f "$BIN_DIR/envkey"
    info "removing $SHARE_DIR$MODE_SHARE"
    [[ $dry_run -eq 0 ]] && rm -rf "$SHARE_DIR"
    info "done. Keychain entries are kept; remove them via Keychain Access if desired."
    exit 0
}

[[ $mode == "uninstall" ]] && uninstall

info "installing envkey (dry_run=$dry_run)"

# 1) binary
[[ $dry_run -eq 0 ]] && mkdir -p "$BIN_DIR"
if [[ $dry_run -eq 0 ]]; then
    cp "$SRC_DIR/src/envkey" "$BIN_DIR/envkey"
    chmod +x "$BIN_DIR/envkey"
else
    echo "  cp $SRC_DIR/src/envkey -> $BIN_DIR/envkey"
fi
info "binary -> $BIN_DIR/envkey$MODE_BIN"

# 2) collect snippets
[[ $dry_run -eq 0 ]] && mkdir -p "$SHARE_DIR"
if [[ $dry_run -eq 0 ]]; then
    cp "$SRC_DIR/src/envkey.collect"    "$SHARE_DIR/envkey.collect"
    cp "$SRC_DIR/src/envkey.collect.fish" "$SHARE_DIR/envkey.collect.fish"
else
    echo "  cp src/envkey.collect* -> $SHARE_DIR/"
fi
info "collects -> $SHARE_DIR$MODE_SHARE"

# 2b) ensure the secret-name list file exists (so startup loop has a target)
[[ $dry_run -eq 0 ]] && mkdir -p "$HOME/.config/fish"
if ! [[ -f "$HOME/.config/fish/secret-names" ]]; then
    [[ $dry_run -eq 0 ]] && touch "$HOME/.config/fish/secret-names"
    info "created $HOME/.config/fish/secret-names (empty list)"
fi

# 3) wiring
wire_one() {
    local sh="$1" f cmd
    f="$(startup_file "$sh")"
    [[ -f "$f" ]] || { [[ $dry_run -eq 0 ]] && { mkdir -p "$(dirname "$f")"; touch "$f"; }; info "creating $f"; }
    wired "$f" && { info "$f already wired, skip"; return; }
    info "wiring $f"
    [[ $dry_run -eq 0 ]] || return
    case "$sh" in
        bash|zsh)
            cmd='if [ -r "'"$HOME"'/.local/share/envkey/envkey.collect" ]; then . "$HOME/.local/share/envkey/envkey.collect"; fi'
            ;;
        fish)
            cmd='[ -r "'"$HOME"'/.local/share/envkey/envkey.collect.fish" ]; and source "'"$HOME"'/.local/share/envkey/envkey.collect.fish"'
            ;;
    esac
    cat >> "$f" <<EOF

$STAMP
# envkey: load secrets from macOS Keychain. manage: envkey set/del/list
$cmd
$STAMP_END
EOF
}

if [[ ${#HOOKS[@]} -eq 0 ]]; then
    warn "no shell detected (bash/zsh/fish). Wire the collect snippets manually."
else
    info "shells detected: ${HOOKS[*]}"
    for sh in "${HOOKS[@]}"; do wire_one "$sh"; done
fi

echo "$PATH" | grep -qE "(^|:)$BIN_DIR(:|$)" \
    && info "PATH ok ($BIN_DIR present)" \
    || warn "$BIN_DIR not in PATH; add it to make 'envkey' available."

info "done. Open a new terminal to load secrets; current shell can source the collect snippet."

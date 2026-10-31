# lib/opennr.sh: logic for opennr.conf (see that file for usage and settings).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

# ScopeBuddy sources this with `set -eo pipefail`; don't let a failure here abort the launch.
scb_guard_begin

OPENNR_ROOT="${OPENNR_ROOT:-$SCB_DLLS/opennr}"
OPENNR_MODE="${OPENNR_MODE:-on}"
OPENNR_PROXY="${OPENNR_PROXY:-dxgi.dll}"
OPENNR_CHECK_HOURS="${OPENNR_CHECK_HOURS:-24}"
OPENNR_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/opennr.log"

_on_log() { scb_log "$OPENNR_LOG" opennr "$*"; }

# Download the latest release into $OPENNR_ROOT/<tag> if it isn't there yet
_on_update() {
    local stamp="$OPENNR_ROOT/.last_check" info tag url sha tmp src
    scb_fresh "$stamp" "$OPENNR_CHECK_HOURS" && return 0
    command -v curl >/dev/null && command -v python3 >/dev/null || { _on_log "update check needs curl and python3"; return 1; }
    info=$(scb_host curl -fsSL --connect-timeout 5 --max-time 15 \
           https://api.github.com/repos/MatheusFerreiraS/OpenNR-OptiScaler/releases/latest \
         | scb_host python3 -I -c '
import json, sys
r = json.load(sys.stdin)
a = next(a for a in r["assets"] if a["name"].endswith(".zip"))
print(r["tag_name"], a["browser_download_url"], (a.get("digest") or "").removeprefix("sha256:"))') \
        || { _on_log "couldn't look up the latest release"; return 1; }
    read -r tag url sha <<<"$info"
    [ -d "$OPENNR_ROOT/$tag" ] && { : >"$stamp"; return 0; }

    _on_log "downloading $tag"
    tmp=$(mktemp -d "$OPENNR_ROOT/.dl.XXXXXX") || return 1
    if ! scb_fetch "$url" "$tmp/r.zip" 600; then
        _on_log "download failed: $url"; rm -rf "$tmp"; return 1
    fi
    if [ -z "$sha" ] || [ "$(scb_sha "$tmp/r.zip")" != "$sha" ]; then
        _on_log "checksum mismatch for $url; not using it"; rm -rf "$tmp"; return 1
    fi
    mkdir "$tmp/x"
    if ! scb_unzip_all "$tmp/r.zip" "$tmp/x" 2>/dev/null; then
        _on_log "couldn't extract $url (need bsdtar or unzip)"; rm -rf "$tmp"; return 1
    fi
    src=$(dirname "$(find "$tmp/x" -name OptiScaler.dll -print -quit)")
    if [ ! -f "$src/OptiScaler.dll" ]; then
        _on_log "no OptiScaler.dll in $url"; rm -rf "$tmp"; return 1
    fi
    mv "$src" "$OPENNR_ROOT/$tag" && rm -rf "$tmp"
    : >"$stamp"
    _on_log "installed $tag"
}

_on_latest() {
    find "$OPENNR_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f\n' 2>/dev/null | sort -rV | head -n1
}

_on_install() {   # gamedir tag
    local gd="$1" tag="$2" src="$OPENNR_ROOT/$2" b
    if [ "$(cat "$gd/.opennr-tag" 2>/dev/null)" != "$tag" ] || [ ! -f "$gd/$OPENNR_PROXY" ]; then
        cp -f "$src/OptiScaler.dll" "$gd/$OPENNR_PROXY"
        cp -rf "$src/OptiScaler" "$src/shaders" "$gd/"
        [ -f "$gd/OptiScaler.ini" ] || cp -f "$src/OptiScaler.ini" "$gd/OptiScaler.ini"
        printf '%s' "$tag" >"$gd/.opennr-tag"
        _on_log "installed $tag into $gd as $OPENNR_PROXY"
    fi
    for b in dlssnr_on_amd_weights.bin; do
        [ -f "$OPENNR_ROOT/backend/$b" ] && cp -nf "$OPENNR_ROOT/backend/$b" "$gd/$b"
    done
    if [ -f "$OPENNR_ROOT/backend/dlssnr_amd_pass1.dll" ]; then
        for b in 1 2 3; do cp -nf "$OPENNR_ROOT/backend/dlssnr_amd_pass1.dll" "$gd/dlssnr_amd_pass$b.dll"; done
    fi
    if [ -n "${OPENNR_NR_BACKEND:-}" ]; then
        sed -i "s/^NrBackend *=.*/NrBackend=$OPENNR_NR_BACKEND/" "$gd/OptiScaler.ini"
    fi
}

if declare -F SCB_GetGameDir >/dev/null && [ -n "${command:-}" ]; then
    _on_gd=$(SCB_GetGameDir "$command" 2>/dev/null)
    if [ ! -d "${_on_gd:-}" ]; then
        _on_log "couldn't find the game folder from: $command"
    elif [ "$OPENNR_MODE" = on ]; then
        mkdir -p "$OPENNR_ROOT/backend"
        if command -v flock >/dev/null && exec {_on_lockfd}>"$OPENNR_ROOT/.lock"; then
            flock -w 300 "$_on_lockfd"
        fi
        _on_update
        _on_tag=$(_on_latest)
        if [ -n "$_on_tag" ]; then
            _on_install "$_on_gd" "$_on_tag"
            case "$WINEDLLOVERRIDES" in *"${OPENNR_PROXY%.dll}="*) ;; *) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}${OPENNR_PROXY%.dll}=n,b" ;; esac
            unset PROTON_USE_OPTISCALER PROTON_OPTISCALER_NAME
        else
            _on_log "no release downloaded yet; see $OPENNR_LOG"
        fi
        [ -n "${_on_lockfd:-}" ] && exec {_on_lockfd}>&-
    elif [ "$OPENNR_MODE" = off ]; then
        rm -f "$_on_gd/$OPENNR_PROXY" "$_on_gd/.opennr-tag"
        _on_log "removed $OPENNR_PROXY from $_on_gd"
    else
        _on_log "unknown OPENNR_MODE='$OPENNR_MODE' (use on|off)"
    fi
else
    _on_log "SCB_GetGameDir or \$command unavailable; nothing done"
fi

unset -f _on_log _on_update _on_latest _on_install
unset _on_gd _on_tag _on_lockfd

scb_guard_end

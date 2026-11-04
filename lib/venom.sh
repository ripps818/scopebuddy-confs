# lib/venom.sh: logic for venom.conf (see that file for usage and settings).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

# ScopeBuddy sources this with `set -eo pipefail`; don't let a failure here abort the launch.
scb_guard_begin

VENOM_ROOT="${VENOM_ROOT:-$SCB_DLLS/venom}"
VENOM_MODE="${VENOM_MODE:-on}"
VENOM_CHANNEL="${VENOM_CHANNEL:-release}"
VENOM_TAG="${VENOM_TAG:-}"
VENOM_PROXY="${VENOM_PROXY:-dxgi.dll}"
VENOM_CHECK_HOURS="${VENOM_CHECK_HOURS:-24}"
VENOM_UMU_SECONDS="${VENOM_UMU_SECONDS:-180}"
VENOM_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/venom.log"
_VENOM_API="https://api.github.com/repos/LorenzoKy/Optiscaler-Venom/releases"

_vn_log() { scb_log "$VENOM_LOG" venom "$*"; }

# Print "<tag> <url> <sha256-url>" for the wanted release.
_vn_lookup() {
    local path
    if [ -n "$VENOM_TAG" ]; then path="/tags/$VENOM_TAG"
    elif [ "$VENOM_CHANNEL" = nightly ]; then path="?per_page=1"
    else path="/latest"; fi
    scb_host curl -fsSL --connect-timeout 5 --max-time 15 "$_VENOM_API$path" \
        | scb_host python3 -I -c '
import json, sys
r = json.load(sys.stdin)
if isinstance(r, list):
    r = r[0]
a = {x["name"]: x["browser_download_url"] for x in r["assets"]}
z = next(n for n in a if n.endswith(".7z"))
print(r["tag_name"], a[z], a.get(z + ".sha256", ""))'
}

# Download the wanted release into $VENOM_ROOT/<tag> if it isn't there yet
_vn_update() {
    local stamp="$VENOM_ROOT/.last_check-${VENOM_TAG:-$VENOM_CHANNEL}" info tag url shaurl want tmp src
    if [ -n "$VENOM_TAG" ] && [ -f "$VENOM_ROOT/$VENOM_TAG/OptiScaler.dll" ]; then return 0; fi
    scb_fresh "$stamp" "$VENOM_CHECK_HOURS" && return 0
    command -v curl >/dev/null && command -v python3 >/dev/null || { _vn_log "update check needs curl and python3"; return 1; }
    info=$(_vn_lookup) || { _vn_log "couldn't look up the release (channel=$VENOM_CHANNEL tag=${VENOM_TAG:-none})"; return 1; }
    read -r tag url shaurl <<<"$info"
    if [ -f "$VENOM_ROOT/$tag/OptiScaler.dll" ]; then : >"$stamp"; return 0; fi

    _vn_log "downloading $tag"
    tmp=$(mktemp -d "$VENOM_ROOT/.dl.XXXXXX") || return 1
    if [ -z "$shaurl" ] || ! scb_fetch "$shaurl" "$tmp/r.sha256" 60; then
        _vn_log "no .sha256 for $tag; not using it"; rm -rf "$tmp"; return 1
    fi
    if ! scb_fetch "$url" "$tmp/r.7z" 600; then
        _vn_log "download failed: $url"; rm -rf "$tmp"; return 1
    fi
    want=$(awk '{print $1; exit}' "$tmp/r.sha256")
    if [ -z "$want" ] || [ "$(scb_sha "$tmp/r.7z")" != "$want" ]; then
        _vn_log "checksum mismatch for $url; not using it"; rm -rf "$tmp"; return 1
    fi
    mkdir "$tmp/x"
    # libarchive's bsdtar reads .7z; 7z/7za/7zr work too
    if command -v bsdtar >/dev/null; then scb_host bsdtar -xf "$tmp/r.7z" -C "$tmp/x"
    elif command -v 7z >/dev/null; then scb_host 7z x -y -o"$tmp/x" "$tmp/r.7z" >/dev/null
    elif command -v 7za >/dev/null; then scb_host 7za x -y -o"$tmp/x" "$tmp/r.7z" >/dev/null
    elif command -v 7zr >/dev/null; then scb_host 7zr x -y -o"$tmp/x" "$tmp/r.7z" >/dev/null
    else false; fi 2>/dev/null || { _vn_log "couldn't extract $url (need bsdtar or 7z)"; rm -rf "$tmp"; return 1; }
    src=$(dirname "$(find "$tmp/x" -name OptiScaler.dll -print -quit)")
    if [ ! -f "$src/OptiScaler.dll" ]; then
        _vn_log "no OptiScaler.dll in $url"; rm -rf "$tmp"; return 1
    fi
    rm -rf "$VENOM_ROOT/$tag"
    mv "$src" "$VENOM_ROOT/$tag" && rm -rf "$tmp"
    : >"$stamp"
    _vn_log "installed $tag"
}

# Newest downloaded build for the channel (the pinned tag if set)
_vn_latest() {
    if [ -n "$VENOM_TAG" ]; then [ -f "$VENOM_ROOT/$VENOM_TAG/OptiScaler.dll" ] && printf '%s' "$VENOM_TAG"; return 0; fi
    if [ "$VENOM_CHANNEL" = nightly ]; then
        find "$VENOM_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'opti-venom-*nightly-*' -printf '%f\n' 2>/dev/null | sort -V | tail -n1
    else
        find "$VENOM_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'opti-venom-v*' ! -name '*nightly*' -printf '%f\n' 2>/dev/null | sort -V | tail -n1
    fi
}

_vn_gd=""
declare -F SCB_GetGameDir >/dev/null && [ -n "${command:-}" ] && _vn_gd=$(SCB_GetGameDir "$command" 2>/dev/null) || true
# remove a game-folder install left by an older version of this conf (the only thing ever touched there)
if [ -n "$_vn_gd" ] && [ -f "$_vn_gd/.venom-tag" ]; then
    rm -f "$_vn_gd/$VENOM_PROXY" "$_vn_gd/.venom-tag"; _vn_log "removed the old game-folder install from $_vn_gd"
fi

case "$VENOM_MODE" in
    on)
        if [ -z "${STEAM_COMPAT_DATA_PATH:-}" ]; then
            _vn_log "no Proton prefix (STEAM_COMPAT_DATA_PATH unset); nothing done"
        else
            export LOW_LATENCY_LAYER="${LOW_LATENCY_LAYER:-1}"   # like fsr4/cyboman: Venom's FSR 4 path wants the low latency layer
            scb_opti_on || export PROTON_USE_OPTISCALER=1       # Proton's OptiScaler is what gets replaced
            [ "$VENOM_PROXY" != dxgi.dll ] && export PROTON_OPTISCALER_NAME="$VENOM_PROXY"
            mkdir -p "$VENOM_ROOT"
            if command -v flock >/dev/null && exec {_vn_lockfd}>"$VENOM_ROOT/.lock"; then
                flock -w 300 "$_vn_lockfd"
            fi
            _vn_update
            _vn_tag=$(_vn_latest)
            if [ -n "$_vn_tag" ]; then
                scb_umu_start "$VENOM_ROOT/$_vn_tag" "$VENOM_UMU_SECONDS" _vn_log "Venom $_vn_tag"
            else
                _vn_log "no release downloaded yet; see $VENOM_LOG"
            fi
            [ -n "${_vn_lockfd:-}" ] && exec {_vn_lockfd}>&-
        fi ;;
    off) ;;
    *) _vn_log "unknown VENOM_MODE='$VENOM_MODE' (use on|off)" ;;
esac

unset -f _vn_log _vn_lookup _vn_update _vn_latest
unset _vn_gd _vn_tag _vn_lockfd

scb_guard_end

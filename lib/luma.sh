# lib/luma.sh: logic for luma.conf (see that file for usage and settings).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

# ScopeBuddy sources this with `set -eo pipefail`; don't let a failure here abort the launch.
scb_guard_begin

LUMA_ROOT="$SCB_DLLS/luma"
LUMA_CHECK_HOURS="${LUMA_CHECK_HOURS:-24}"
LUMA_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/luma.log"
LUMA_API=https://api.github.com/repos/Filoppi/Luma-Framework/releases/latest

_lu_log() { scb_log "$LUMA_LOG" luma "$*"; }

# keep the release's asset list ($LUMA_ROOT/release.json) fresh
_lu_refresh() {
    local stamp="$LUMA_ROOT/.last_check" tmp
    scb_fresh "$stamp" "$LUMA_CHECK_HOURS" && [ -s "$LUMA_ROOT/release.json" ] && return 0
    tmp="$LUMA_ROOT/release.json.new"
    if scb_fetch "$LUMA_API" "$tmp" 30 && [ -s "$tmp" ]; then
        mv -f "$tmp" "$LUMA_ROOT/release.json"; : >"$stamp"
    else
        rm -f "$tmp"; _lu_log "couldn't look up the latest release"
        [ -s "$LUMA_ROOT/release.json" ]
    fi
}

# prints: "<asset name> <url> <sha256>" for the wanted mod. $1 = mod text, $2 = game folder name (guess)
_lu_pick() {
    command -v python3 >/dev/null || return 1
    scb_host python3 -I -c '
import json, re, sys, os
rel = json.load(open(sys.argv[1]))
want, guess = sys.argv[2], sys.argv[3]
test, dev, x32 = (os.environ.get(k) == "1" for k in ("LUMA_TEST", "LUMA_DEV", "LUMA_X32"))
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
if norm(want) == "generic": want = "Generic_Mod"
# asset = Luma-<Game>[-Test|-Dev][-x32].zip
mods = {}
for a in rel["assets"]:
    m = re.fullmatch(r"Luma-(.+?)(-Test|-Dev)?(-x32)?\.zip", a["name"])
    if m: mods.setdefault(norm(m[1]), {})[(m[2] or "", bool(m[3]))] = a
cand = mods.get(norm(want or guess))
if not cand or (not want and norm(guess) in ("genericmod", "graphicsanalyzer")): sys.exit(2)
suffix = "-Test" if test else "-Dev" if dev else ""
# 64-bit unless asked for x32 or only x32 exists
bits = [x32] if x32 else [False, True]
a = next((cand[(suffix, b)] for b in bits if (suffix, b) in cand), None)
if not a: sys.exit(3)
print(rel["tag_name"], a["name"], a["browser_download_url"], (a.get("digest") or "").removeprefix("sha256:"))
' "$LUMA_ROOT/release.json" "$1" "$2"
}

# download an asset into $LUMA_ROOT/pkg/<name>/ (zip + .sha), only when the digest changed
_lu_get() {   # name url sha
    local d="$LUMA_ROOT/pkg/${1%.zip}" tmp
    [ -s "$d/$1" ] && [ "$(cat "$d/.sha" 2>/dev/null)" = "$3" ] && [ -n "$3" ] && return 0
    mkdir -p "$d" && tmp=$(mktemp -d "$LUMA_ROOT/.dl.XXXXXX") || return 1
    _lu_log "downloading $1"
    if ! scb_fetch "$2" "$tmp/$1" 900; then _lu_log "download failed: $2"; rm -rf "$tmp"; return 1; fi
    if [ -z "$3" ] || [ "$(scb_sha "$tmp/$1")" != "$3" ]; then
        _lu_log "checksum mismatch for $1; not using it"; rm -rf "$tmp"; return 1
    fi
    mv -f "$tmp/$1" "$d/$1" && printf '%s' "$3" >"$d/.sha"; rm -rf "$tmp"
}

_lu_install() {   # gamedir name sha proxy-name
    local gd="$1" zip="$LUMA_ROOT/pkg/${2%.zip}/$2" stamp="$3 $4"
    [ "$(cat "$gd/.luma-sha" 2>/dev/null)" = "$stamp" ] && [ -f "$gd/$4" ] && return 0
    # updating, switching mod, or switching between dxgi / OptiScaler mode: clean out the previous install first
    _lu_remove "$gd"
    # keep a foreign dxgi.dll so LUMA_MODE=off can restore it
    if [ -f "$gd/dxgi.dll" ] && [ ! -e "$gd/dxgi.dll.pre-luma" ]; then
        mv -f "$gd/dxgi.dll" "$gd/dxgi.dll.pre-luma"
    fi
    scb_unzip_all "$zip" "$gd" 2>/dev/null || { _lu_log "couldn't extract $zip (need bsdtar, unzip or python3)"; return 1; }
    scb_host python3 -I -c 'import sys,zipfile; print("\n".join(n for n in zipfile.ZipFile(sys.argv[1]).namelist() if not n.endswith("/")))' \
        "$zip" >"$gd/.luma-files" 2>/dev/null
    if [ "$4" != dxgi.dll ]; then   # Luma's ReShade is loaded by OptiScaler instead of acting as the dxgi proxy
        mv -f "$gd/dxgi.dll" "$gd/$4" && sed -i "s/^dxgi\.dll\$/$4/" "$gd/.luma-files"
    fi
    printf '%s' "$stamp" >"$gd/.luma-sha"
    _lu_log "installed $2 into $gd (ReShade as $4)"
}

_lu_remove() {   # gamedir
    local gd="$1" f
    [ -f "$gd/.luma-files" ] || return 0
    while IFS= read -r f; do rm -f "$gd/$f"; done <"$gd/.luma-files"
    rm -rf "$gd/Luma" 2>/dev/null
    rm -f "$gd/.luma-files" "$gd/.luma-sha"
    [ -e "$gd/dxgi.dll.pre-luma" ] && mv -f "$gd/dxgi.dll.pre-luma" "$gd/dxgi.dll"
    _lu_log "removed Luma from $gd"
}

# Prints Unity_Engine / Unreal_Engine when the game folder looks like one (and sets _lu_x32=1 for a 32-bit Unity player)
_lu_engine() {   # gamedir
    local gd="$1" up
    _lu_x32=0
    if [ -f "$gd/UnityPlayer.dll" ]; then
        up="$gd/UnityPlayer.dll"
        # PE machine type: 0x014c = 32-bit
        [ "$(scb_host python3 -I -c 'import struct,sys
f=open(sys.argv[1],"rb"); f.seek(0x3c); o=struct.unpack("<I",f.read(4))[0]; f.seek(o+4); print(struct.unpack("<H",f.read(2))[0])' "$up" 2>/dev/null)" = 332 ] && _lu_x32=1
        echo Unity_Engine
    elif compgen -G "$gd/*-Shipping.exe" >/dev/null || [ -d "$gd/../../Content/Paks" ] || [ -d "$gd/../../../Engine/Binaries" ]; then
        echo Unreal_Engine
    fi
}

_lu_gd="${LUMA_GAME_DIR:-}"
if [ -z "$_lu_gd" ] && declare -F SCB_GetGameDir >/dev/null && [ -n "${command:-}" ]; then
    _lu_gd=$(SCB_GetGameDir "$command" 2>/dev/null)
fi
# Proton's OptiScaler folder in the prefix
_lu_umu="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/windows/system32/umu"
[ -n "${STEAM_COMPAT_DATA_PATH:-}" ] || _lu_umu=/nonexistent
if [ ! -d "${_lu_gd:-}" ]; then
    _lu_log "couldn't find the game folder (set LUMA_GAME_DIR); nothing done"
elif [ "${LUMA_MODE:-on}" = off ]; then
    _lu_remove "$_lu_gd"; [ -d "$_lu_umu" ] && _lu_remove "$_lu_umu"
elif [ "${LUMA_MODE:-on}" != on ]; then
    _lu_log "unknown LUMA_MODE='$LUMA_MODE' (use on|off)"
else
    mkdir -p "$LUMA_ROOT"
    # folder name of the Steam install, for the LUMA_MOD guess
    _lu_dirname="${STEAM_COMPAT_INSTALL_PATH:-}"; _lu_dirname="${_lu_dirname%/}"; _lu_dirname="${_lu_dirname##*/}"
    _lu_x32=0
    # explicit LUMA_MOD, else the Steam folder name, else the engine (Unity / Unreal) as a fallback to the generic mod
    if _lu_refresh && { _lu_info=$(_lu_pick "${LUMA_MOD:-}" "$_lu_dirname") ||
        { [ -z "${LUMA_MOD:-}" ] && [ "${LUMA_ENGINE:-on}" != off ] && _lu_eng=$(_lu_engine "$_lu_gd") && [ -n "$_lu_eng" ] &&
          _lu_log "no game-specific mod for '$_lu_dirname'; detected $_lu_eng" &&
          _lu_info=$(LUMA_X32="${LUMA_X32:-$_lu_x32}" _lu_pick "$_lu_eng" ""); }; }; then
        read -r _lu_tag _lu_name _lu_url _lu_sha <<<"$_lu_info"
        if _lu_get "$_lu_name" "$_lu_url" "$_lu_sha" || [ -s "$LUMA_ROOT/pkg/${_lu_name%.zip}/$_lu_name" ]; then
            _lu_sha=$(cat "$LUMA_ROOT/pkg/${_lu_name%.zip}/.sha" 2>/dev/null || echo "$_lu_sha")
            # With OptiScaler on, it owns dxgi.dll and loads Luma's ReShade (as ReShade64.dll) itself
            if scb_opti_on; then _lu_proxy=ReShade64.dll; else _lu_proxy=dxgi.dll; fi
            if [ "$_lu_proxy" = dxgi.dll ]; then
                [ -d "$_lu_umu" ] && _lu_remove "$_lu_umu"   # left over from an OptiScaler launch
                _lu_install "$_lu_gd" "$_lu_name" "$_lu_sha" dxgi.dll &&
                    case "${WINEDLLOVERRIDES:-}" in *dxgi=*) ;; *) export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}dxgi=n,b" ;; esac
            else
                # OptiScaler's wiki: rename ReShade's dll to ReShade64.dll and put it "next to OptiScaler", which under
                # Proton is the prefix's system32/umu (where fsr-multi / mfgunlocker / optipatcher also put things).
                # So the whole Luma package goes there; the game folder is a last resort (LUMA_OPTI_DIR=game, or both),
                # used by default only when the prefix is unknown.
                _lu_where="${LUMA_OPTI_DIR:-umu}"
                if [ "$_lu_where" != game ] && ! { [ "$_lu_umu" != /nonexistent ] && mkdir -p "$_lu_umu"; }; then
                    _lu_log "no usable $_lu_umu (STEAM_COMPAT_DATA_PATH unset?); falling back to the game folder"
                    _lu_where=game
                fi
                _lu_ok=0
                case "$_lu_where" in
                    game) [ -d "$_lu_umu" ] && _lu_remove "$_lu_umu" ;;
                    umu)  _lu_remove "$_lu_gd" ;;
                esac
                case "$_lu_where" in game|both)
                    _lu_install "$_lu_gd" "$_lu_name" "$_lu_sha" ReShade64.dll && _lu_ok=1 ;;
                esac
                case "$_lu_where" in umu|both)
                    _lu_install "$_lu_umu" "$_lu_name" "$_lu_sha" ReShade64.dll && _lu_ok=1 ;;
                esac
                if [ "$_lu_ok" = 1 ]; then
                    PROTON_OPTISCALER_CONFIG="${PROTON_OPTISCALER_CONFIG:+$PROTON_OPTISCALER_CONFIG;}Plugins.LoadReshade=true"
                    [ "${LUMA_D3D12_DEVICE:-0}" = 1 ] && PROTON_OPTISCALER_CONFIG="$PROTON_OPTISCALER_CONFIG;Hotfix.CreateD3D12DeviceForLuma=true"
                    export PROTON_OPTISCALER_CONFIG
                fi
            fi
        fi
    else
        _lu_log "no matching mod for LUMA_MOD='${LUMA_MOD:-}' / folder '$_lu_dirname' (or no release info); nothing installed"
    fi
fi

unset -f _lu_engine _lu_log _lu_refresh _lu_pick _lu_get _lu_install _lu_remove
unset _lu_eng _lu_x32 _lu_f _lu_where _lu_ok _lu_umu _lu_proxy _lu_gd _lu_dirname _lu_info _lu_tag _lu_name _lu_url _lu_sha

scb_guard_end

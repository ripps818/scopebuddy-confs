# lib/mfgunlocker.sh: logic for mfgunlocker.conf (see that file for usage and settings).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

scb_guard_begin
MFGU_ROOT="$SCB_DLLS/mfg-unlocker"
MFGU_FALLBACK_TAG=v1.6.1
MFGU_CHECK_HOURS="${MFGUNLOCKER_CHECK_HOURS:-24}"
MFGU_UMU="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/windows/system32/umu"
MFGU_PLUGINS="$MFGU_UMU/plugins"
MFGU_LOG="$SCB_CONFIGDIR/mfgunlocker.log"

_mfgu_log() { scb_log "$MFGU_LOG" mfgu "$1"; }

# Sets MFGU_TAG: the pin, else the latest release (looked up at most every
# MFGU_CHECK_HOURS), else the last known tag, newest cached tag or the fallback.
_mfgu_resolve() {
    local stamp="$MFGU_ROOT/.last_check" tagfile="$MFGU_ROOT/.latest_tag" tag=""
    if [ -n "${MFGUNLOCKER_TAG:-}" ]; then MFGU_TAG="$MFGUNLOCKER_TAG"; return 0; fi
    mkdir -p "$MFGU_ROOT" 2>/dev/null || true
    if [ -s "$tagfile" ] && scb_fresh "$stamp" "$MFGU_CHECK_HOURS"; then
        MFGU_TAG=$(cat "$tagfile"); return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        tag=$(scb_host curl -fsSL --connect-timeout 5 --max-time 15 \
            https://api.github.com/repos/dashdogy/MFG-Unlocker/releases/latest 2>/dev/null |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    fi
    case "$tag" in
        v[0-9]*) printf '%s\n' "$tag" >"$tagfile" 2>/dev/null; : >"$stamp" 2>/dev/null ;;
        *)  _mfgu_log "couldn't look up the latest release"
            tag=$(cat "$tagfile" 2>/dev/null)
            [ -n "$tag" ] || tag=$(find "$MFGU_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f\n' 2>/dev/null | sort -rV | head -n1) ;;
    esac
    MFGU_TAG="${tag:-$MFGU_FALLBACK_TAG}"
}

_mfgu_get() {
    [ -s "$MFGU_DLL" ] && return 0
    local tmp zip want got
    mkdir -p "$MFGU_ROOT" && tmp=$(mktemp -d "$MFGU_ROOT/.dl.XXXXXX") || { _mfgu_log "couldn't create temp dir"; return 1; }
    zip="MFGUnlocker-$MFGU_TAG.zip"
    if ! scb_fetch "$MFGU_URL/SHA256SUMS.txt" "$tmp/SHA256SUMS" 120 || ! scb_fetch "$MFGU_URL/$zip" "$tmp/$zip" 120; then
        _mfgu_log "download failed ($MFGU_TAG)"; rm -rf "$tmp"; return 1
    fi
    want=$(awk -v f="$zip" '$2==f{print tolower($1)}' "$tmp/SHA256SUMS")
    got=$(scb_sha "$tmp/$zip")
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        _mfgu_log "checksum mismatch for $zip; not using it"; rm -rf "$tmp"; return 1
    fi
    if ! scb_unzip_one "$tmp/$zip" MFGUnlocker.dll "$tmp/MFGUnlocker.dll" || [ ! -s "$tmp/MFGUnlocker.dll" ]; then
        _mfgu_log "couldn't extract MFGUnlocker.dll (need unzip, bsdtar or python3)"; rm -rf "$tmp"; return 1
    fi
    if ! { mkdir -p "$MFGU_ROOT/$MFGU_TAG" && mv -f "$tmp/MFGUnlocker.dll" "$MFGU_DLL"; }; then
        _mfgu_log "couldn't store MFGUnlocker.dll"; rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
    _mfgu_log "installed MFGUnlocker.dll from $MFGU_TAG (sha256 ok)"
}

if [ "${MFGUNLOCKER_REMOVE:-0}" = 1 ]; then
    # also the old location, from before the shared plugins folder
    if [ -n "${STEAM_COMPAT_DATA_PATH:-}" ]; then
        rm -f "$MFGU_PLUGINS/MFGUnlocker.asi" "$MFGU_UMU/OptiScaler/plugins/MFGUnlocker.asi" 2>/dev/null || true
        _mfgu_log "removed MFGUnlocker.asi"
    fi
elif [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] && [ -n "${PROTON_USE_OPTISCALER:-}" ] && [ "$PROTON_USE_OPTISCALER" != 0 ]; then
    _mfgu_resolve
    MFGU_DLL="$MFGU_ROOT/$MFGU_TAG/MFGUnlocker.dll"
    MFGU_URL="https://github.com/dashdogy/MFG-Unlocker/releases/download/$MFGU_TAG"
    if _mfgu_get; then
        # a copy left in the old location would never load now; tidy it away
        rm -f "$MFGU_UMU/OptiScaler/plugins/MFGUnlocker.asi" 2>/dev/null || true
        if mkdir -p "$MFGU_PLUGINS" &&
            { cmp -s "$MFGU_DLL" "$MFGU_PLUGINS/MFGUnlocker.asi" 2>/dev/null || cp -f "$MFGU_DLL" "$MFGU_PLUGINS/MFGUnlocker.asi"; }; then
            PROTON_OPTISCALER_CONFIG="${PROTON_OPTISCALER_CONFIG:+$PROTON_OPTISCALER_CONFIG;}Plugins.LoadAsiPlugins=true;Plugins.Path=c:\\windows\\system32\\umu\\plugins;FrameGen.FGOutput=XeFG"
            export PROTON_OPTISCALER_CONFIG
        else
            _mfgu_log "couldn't copy MFGUnlocker.asi into the prefix"
        fi
    fi
else
    _mfgu_log "needs PROTON_USE_OPTISCALER set above the source line; skipping"
fi

unset -f _mfgu_log _mfgu_resolve _mfgu_get

scb_guard_end
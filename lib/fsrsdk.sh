# lib/fsrsdk.sh: logic for fsrsdk.conf (see that file for usage and FSR4SDK_CLEANUP).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

export LOW_LATENCY_LAYER=1

FSR4SDK_ROOT="${FSR4SDK_ROOT:-$SCB_DLLS/fsrsdk}"
FSR4SDK_REF="${FSR4SDK_REF:-main}"
FSR4SDK_CHECK_HOURS="${FSR4SDK_CHECK_HOURS:-24}"
FSR4SDK_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/fsrsdk.log"
FSR4SDK_DST="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/windows/system32/umu/OptiScaler"
FSR4SDK_FILES="amd_fidelityfx_upscaler_dx12.dll amd_fidelityfx_upscaler_vk.dll"
_FSR4SDK_REPO="GPUOpen-LibrariesAndSDKs/FidelityFX-SDK"
_FSR4SDK_PATH="Kits/FidelityFX/signedbin"

# the old name for the cleanup flag
[ "${FSR412_CLEANUP:-0}" = 1 ] && FSR4SDK_CLEANUP=1

_fs_log() { scb_log "$FSR4SDK_LOG" fsrsdk "$*"; }

# Download the DLLs for the newest commit that touched signedbin/ (or the pinned ref) into $FSR4SDK_ROOT.
_fs_update() {
    scb_guard_begin
    local stamp="$FSR4SDK_ROOT/.last_check" sha tmp f
    if scb_fresh "$stamp" "$FSR4SDK_CHECK_HOURS" && [ -s "$FSR4SDK_ROOT/${FSR4SDK_FILES%% *}" ]; then scb_guard_end; return 0; fi
    mkdir -p "$FSR4SDK_ROOT" || { scb_guard_end; return 1; }
    sha=$(scb_get "https://api.github.com/repos/$_FSR4SDK_REPO/commits?sha=$FSR4SDK_REF&path=$_FSR4SDK_PATH&per_page=1" "Accept: application/vnd.github+json" 2>/dev/null \
          | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -n1 | grep -o '[0-9a-f]\{40\}')
    if [ -z "$sha" ]; then
        _fs_log "couldn't look up the SDK repo (ref $FSR4SDK_REF); using the cached DLLs if any"
        scb_guard_end; return 1
    fi
    if [ "$(cat "$FSR4SDK_ROOT/SHA" 2>/dev/null)" = "$sha" ] && [ -s "$FSR4SDK_ROOT/${FSR4SDK_FILES%% *}" ]; then
        : >"$stamp"; scb_guard_end; return 0
    fi
    tmp=$(mktemp -d "$FSR4SDK_ROOT/.dl.XXXXXX") || { scb_guard_end; return 1; }
    _fs_log "downloading the SDK DLLs from ${sha:0:7} (ref $FSR4SDK_REF)"
    for f in $FSR4SDK_FILES; do
        if ! scb_fetch "https://raw.githubusercontent.com/$_FSR4SDK_REPO/$sha/$_FSR4SDK_PATH/$f" "$tmp/$f" 900 \
           || [ "$(stat -c %s "$tmp/$f" 2>/dev/null || echo 0)" -lt 1000000 ]; then
            _fs_log "download failed for $f; keeping the cached DLLs"; rm -rf "$tmp"; scb_guard_end; return 1
        fi
    done
    for f in $FSR4SDK_FILES; do mv -f "$tmp/$f" "$FSR4SDK_ROOT/$f"; done
    printf '%s\n' "$sha" >"$FSR4SDK_ROOT/SHA"; : >"$stamp"; rm -rf "$tmp"
    _fs_log "installed the SDK DLLs (${sha:0:7})"
    scb_guard_end
}

# Cleanup: set FSR4SDK_CLEANUP=1 above the source line for one launch to remove the files
# this script copied (only byte-identical ones), then drop the flag. Nothing is copied or
# exported on a cleanup launch.
if [ "${FSR4SDK_CLEANUP:-0}" = 1 ]; then
    if [ -n "${STEAM_COMPAT_DATA_PATH:-}" ]; then
        for f in $FSR4SDK_FILES; do
            if [ -f "$FSR4SDK_DST/$f" ] && cmp -s "$FSR4SDK_ROOT/$f" "$FSR4SDK_DST/$f"; then
                rm -f "$FSR4SDK_DST/$f"
            fi
        done
    fi
    unset -f _fs_update _fs_log
    return 0 2>/dev/null || true
fi

if [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] && scb_opti_on; then
    if command -v flock >/dev/null && mkdir -p "$FSR4SDK_ROOT" && exec {_fs_lockfd}>"$FSR4SDK_ROOT/.lock"; then
        flock -w 300 "$_fs_lockfd"
    fi
    _fs_update
    [ -n "${_fs_lockfd:-}" ] && exec {_fs_lockfd}>&-
    if [ -s "$FSR4SDK_ROOT/${FSR4SDK_FILES%% *}" ]; then
        mkdir -p "$FSR4SDK_DST"
        for f in $FSR4SDK_FILES; do
            [ -s "$FSR4SDK_ROOT/$f" ] || continue
            cmp -s "$FSR4SDK_ROOT/$f" "$FSR4SDK_DST/$f" 2>/dev/null || cp -f --reflink=auto "$FSR4SDK_ROOT/$f" "$FSR4SDK_DST/$f"
        done
    else
        _fs_log "no SDK DLLs available (offline on first use?); Proton's own FSR 4 stays"
    fi
fi

# Force OptiScaler onto the INT8 model (RDNA3).
case "${PROTON_OPTISCALER_CONFIG:-}" in
    *FSR.Fsr4GpuSupport=*) ;;
    *)
        PROTON_OPTISCALER_CONFIG="${PROTON_OPTISCALER_CONFIG:+$PROTON_OPTISCALER_CONFIG;}FSR.UpscalerIndex=0;FSR.Fsr4GpuSupport=2"
        export PROTON_OPTISCALER_CONFIG
        ;;
esac
unset -f _fs_update _fs_log
unset _fs_lockfd

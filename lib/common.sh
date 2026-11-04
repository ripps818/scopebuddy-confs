# lib/common.sh: helpers shared by the other lib/*.sh components. Safe to source more than once.
[ -n "${_SCB_COMMON_LOADED:-}" ] && return 0
_SCB_COMMON_LOADED=1

# Everything the confs download or install lives under this one folder (one subfolder per component).
SCB_DLLS="${SCB_DLLS:-${XDG_DATA_HOME:-$HOME/.local/share}/scopebuddy-dlls}"

# ScopeBuddy sources configs with `set -eo pipefail`, so a failing command in a component would
# abort the launch. scb_guard_begin turns both off, scb_guard_end puts back what was on (nesting
# is fine). $- and shopt are read here, in the sourcing shell: a $( ) subshell reports errexit off.
_SCB_GUARD_DEPTH=0
scb_guard_begin() {
    if [ "$_SCB_GUARD_DEPTH" = 0 ]; then
        _SCB_ERREXIT=0; case $- in *e*) _SCB_ERREXIT=1 ;; esac
        _SCB_PIPEFAIL=0; shopt -qo pipefail && _SCB_PIPEFAIL=1
        set +e +o pipefail
    fi
    _SCB_GUARD_DEPTH=$((_SCB_GUARD_DEPTH + 1))
}

scb_guard_end() {
    _SCB_GUARD_DEPTH=$((_SCB_GUARD_DEPTH - 1))
    if [ "$_SCB_GUARD_DEPTH" = 0 ]; then
        [ "$_SCB_PIPEFAIL" = 1 ] && set -o pipefail
        [ "$_SCB_ERREXIT" = 1 ] && set -e
    fi
    true
}

scb_log() {   # logfile tag message
    { printf '%s [%s] appid=%s %s\n' "$(date '+%F %T')" "$2" "${SteamAppId:-${SCB_APPID:-?}}" "$3" >>"$1"; } 2>/dev/null || true
}

# Steam's launch environment can break host tools (curl in particular)
scb_host() { env -u LD_PRELOAD -u LD_LIBRARY_PATH "$@"; }

scb_fetch() {   # url dest [max-seconds]
    if command -v curl >/dev/null 2>&1; then scb_host curl -fsSL --retry 2 --connect-timeout 10 --max-time "${3:-900}" -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then scb_host wget -q -T "${3:-900}" -t 3 -O "$2" "$1"
    else return 1; fi
}

scb_fresh() {   # stamp-file hours: touched within that many hours
    [ -f "$1" ] && [ -z "$(find "$1" -mmin +$(($2 * 60)) 2>/dev/null)" ]
}

scb_sha() { sha256sum "$1" | cut -d' ' -f1; }

scb_unzip_one() {   # zip member dest
    if command -v unzip >/dev/null 2>&1; then scb_host unzip -p "$1" "$2" >"$3"
    elif command -v bsdtar >/dev/null 2>&1; then scb_host bsdtar -xOf "$1" "$2" >"$3"
    elif command -v python3 >/dev/null 2>&1; then scb_host python3 -I -c 'import sys,zipfile; sys.stdout.buffer.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' "$1" "$2" >"$3"
    else return 1; fi
}

scb_unzip_all() {   # zip destdir
    if command -v bsdtar >/dev/null 2>&1; then scb_host bsdtar -xf "$1" -C "$2"
    elif command -v unzip >/dev/null 2>&1; then scb_host unzip -q "$1" -d "$2"
    elif command -v python3 >/dev/null 2>&1; then scb_host python3 -I -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"
    else return 1; fi
}

# Proton's OptiScaler integration is on for any PROTON_USE_OPTISCALER value except off-ish ones
scb_opti_on() {
    case "${PROTON_USE_OPTISCALER:-}" in ""|0|false|no|off) return 1 ;; *) return 0 ;; esac
}

# --- Replace Proton's OptiScaler (in the prefix) with another OptiScaler build -----------------
# Nothing is written to the game folder. Proton puts its own OptiScaler in
# <prefix>/drive_c/windows/system32/umu on every launch, after the confs ran, and md5-checks its files
# before enabling it. So a background loop waits for wineserver (Proton is done by then) and keeps
# overwriting those files with the build in $1. OptiScaler.ini is never touched (Proton writes
# PROTON_OPTISCALER_CONFIG into it). SCB_UMU_EXTRA=("src-file:name-in-umu" ...) adds more root files.
scb_umu_sync() {   # build-dir umu-dir
    local src="$1" umu="$2" t f rel e
    for t in "$umu/OptiScaler.dll" "$umu/${PROTON_OPTISCALER_NAME:-dxgi.dll}"; do
        [ -f "$t" ] && ! cmp -s "$src/OptiScaler.dll" "$t" && cp -f "$src/OptiScaler.dll" "$t"
    done
    mkdir -p "$umu/OptiScaler" 2>/dev/null || return 0
    while IFS= read -r f; do
        rel=${f#"$src/"}
        [ -d "$umu/$rel" ] && rm -rf "$umu/$rel"   # a file name that an earlier version made into a folder
        cmp -s "$f" "$umu/$rel" 2>/dev/null && continue
        case $rel in */*) mkdir -p "$umu/${rel%/*}" 2>/dev/null ;; esac
        cp -f "$f" "$umu/$rel"
    done < <(find "$src/OptiScaler" "$src/shaders" -type f 2>/dev/null)
    # OptiScaler looks for the NVIDIA/nvapi DLLs in OptiScaler/; Proton keeps them one level up
    for f in nvngx_dlss nvngx_dlssd nvngx_dlssg fakenvapi; do
        [ -e "$umu/$f.dll" ] && [ ! -e "$umu/OptiScaler/$f.dll" ] && ln -sf "../$f.dll" "$umu/OptiScaler/$f.dll"
    done
    for e in ${SCB_UMU_EXTRA[@]+"${SCB_UMU_EXTRA[@]}"}; do
        [ -f "${e%%:*}" ] && ! cmp -s "${e%%:*}" "$umu/${e#*:}" && cp -f "${e%%:*}" "$umu/${e#*:}"
    done
    return 0
}

scb_umu_start() {   # build-dir seconds logfunc label [hook-function, run once with the umu dir after the first swap]
    local src="$1" secs="$2" log="$3" label="$4" hook="${5:-}"
    local umu="$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows/system32/umu"
    mkdir -p "$umu" || return 1
    "$log" "umu mode: syncing $label into $umu for up to ${secs}s (after wine starts; nothing goes in the game folder)"
    (
        n=0; w=0; swaps=0
        while ! pgrep -x wineserver >/dev/null && [ "$w" -lt 300 ]; do w=$((w + 1)); sleep 0.2; done
        while [ "$n" -lt $((secs * 5)) ]; do
            scb_umu_sync "$src" "$umu"
            if [ "$swaps" = 0 ] && [ -f "$umu/OptiScaler.dll" ] && cmp -s "$src/OptiScaler.dll" "$umu/OptiScaler.dll"; then
                swaps=1; "$log" "umu: $label in place after $((n / 5))s"
                [ -n "$hook" ] && "$hook" "$umu"
            fi
            # stop once wine exits so Steam doesn't wait on this loop after the game closes
            pgrep -x wineserver >/dev/null || break
            n=$((n + 1)); sleep 0.2
        done
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

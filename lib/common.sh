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

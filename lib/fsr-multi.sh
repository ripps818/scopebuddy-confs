# lib/fsr-multi.sh: logic for fsr-multi.conf (see that file for usage and settings).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
source "$_scb_lib/cyboman-release.sh"
unset _scb_lib

# ScopeBuddy sources this with `set -eo pipefail`; don't let a failure here abort the launch.
scb_guard_begin

FSRMULTI_SRC="$SCB_DLLS/fsr-multi"
FSRMULTI_DST="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/windows/system32/umu/OptiScaler/custom"
FSRMULTI_TARGET="${FSR4_DLL_TARGET:-rx7000}"
FSRMULTI_CYBOMAN="${FSRMULTI_CYBOMAN:-1}"
FSRMULTI_HELIXSR="${FSRMULTI_HELIXSR:-1}"
FSRMULTI_HX_BUILD="${FSRMULTI_HX_BUILD:-0}"
FSRMULTI_CHECK_HOURS="${FSRMULTI_CHECK_HOURS:-24}"
FSRMULTI_HX_ROOT="${HELIXSR_ROOT:-$SCB_DLLS/helixsr}"
FSRMULTI_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/fsr-multi.log"

_fm_log() { scb_log "$FSRMULTI_LOG" fsr-multi "$1"; }

# --- cyboman: newest dll-* release -> $FSRMULTI_SRC/fsr-cyboman-<variant>.dll -------------------------
_fm_cyboman_update() {
    local stamp="$FSRMULTI_SRC/.cyboman-check" tag prefix asset tmp sums want got v member key name n=0
    scb_fresh "$stamp" "$FSRMULTI_CHECK_HOURS" && return 0
    command -v git >/dev/null || { _fm_log "cyboman: needs git to look up the latest release"; return 1; }
    tag=$(scb_cyboman_tag)
    [ -n "$tag" ] || { _fm_log "cyboman: couldn't look up the latest release"; return 1; }
    if [ "$(cat "$FSRMULTI_SRC/cyboman.tag" 2>/dev/null)" = "$tag $FSRMULTI_TARGET" ]; then : >"$stamp"; return 0; fi
    prefix=$(scb_cyboman_prefix "$FSRMULTI_TARGET") || { _fm_log "cyboman: unknown FSR4_DLL_TARGET='$FSRMULTI_TARGET'"; return 1; }
    tmp=$(mktemp -d "$FSRMULTI_SRC/.dl.XXXXXX") || { _fm_log "cyboman: couldn't create a temp dir"; return 1; }
    sums="$tmp/SHA256SUMS"
    if ! scb_fetch "$_CYBOMAN_GH/releases/download/$tag/SHA256SUMS" "$sums"; then
        _fm_log "cyboman: download failed ($tag/SHA256SUMS)"; rm -rf "$tmp"; return 1
    fi
    asset=$(scb_cyboman_asset "$sums" "$prefix")
    [ -n "$asset" ] && _fm_log "cyboman: downloading $asset from $tag"
    if [ -z "$asset" ] || ! scb_fetch "$_CYBOMAN_GH/releases/download/$tag/$asset" "$tmp/$asset"; then
        _fm_log "cyboman: download failed ($tag/${asset:-no matching zip})"; rm -rf "$tmp"; return 1
    fi
    want=$(awk -v f="$asset" '$2==f{print $1}' "$sums"); got=$(scb_sha "$tmp/$asset")
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        _fm_log "cyboman: checksum mismatch for $asset; not using it"; rm -rf "$tmp"; return 1
    fi
    for v in exact lossy 4.1.2l-exact 4.1.2l-lossy; do
        member="$v/amd_fidelityfx_upscaler_dx12.dll"; key="$FSRMULTI_TARGET/$member"
        want=$(awk -v f="$key" '$2==f{print $1}' "$sums")
        [ -n "$want" ] || continue                       # older releases lack some variants
        scb_unzip_one "$tmp/$asset" "$member" "$tmp/$v.dll" 2>/dev/null
        if [ -s "$tmp/$v.dll" ] && [ "$(scb_sha "$tmp/$v.dll")" = "$want" ]; then
            name="fsr-cyboman-${v//./}.dll"
            mv -f "$tmp/$v.dll" "$FSRMULTI_SRC/$name" && n=$((n + 1))
        else
            _fm_log "cyboman: couldn't extract or verify $key; skipped"
        fi
    done
    rm -rf "$tmp"
    if [ "$n" -gt 0 ]; then
        printf '%s %s\n' "$tag" "$FSRMULTI_TARGET" >"$FSRMULTI_SRC/cyboman.tag"; : >"$stamp"
        _fm_log "cyboman: installed $n builds from $tag ($FSRMULTI_TARGET, sha256 ok)"
    fi
}

# --- HelixSR: newest release (pre-releases too) -> $FSRMULTI_HX_ROOT/<tag>, then staged here -------------
_fm_helixsr_update() {
    local stamp="$FSRMULTI_HX_ROOT/.fsrmulti-check" info tag url sumsurl tmp src zip want got
    scb_fresh "$stamp" "$FSRMULTI_CHECK_HOURS" && return 0
    command -v python3 >/dev/null || { _fm_log "helixsr: needs python3 to look up the latest release"; return 1; }
    info=$(scb_host curl -fsSL --connect-timeout 5 --max-time 15 \
           "https://api.github.com/repos/lonewolf0622/HelixSR/releases?per_page=1" \
         | scb_host python3 -I -c '
import json, sys
r = json.load(sys.stdin)[0]
a = {x["name"]: x["browser_download_url"] for x in r["assets"]}
z = next(n for n in a if n.startswith("HelixSR-") and n.endswith(".zip"))
print(r["tag_name"], a[z], a["SHA256SUMS.txt"])') \
        || { _fm_log "helixsr: couldn't look up the latest release"; return 1; }
    read -r tag url sumsurl <<<"$info"
    mkdir -p "$FSRMULTI_HX_ROOT" || return 1
    if [ -d "$FSRMULTI_HX_ROOT/$tag" ]; then : >"$stamp"; return 0; fi
    tmp=$(mktemp -d "$FSRMULTI_HX_ROOT/.dl.XXXXXX") || { _fm_log "helixsr: couldn't create a temp dir"; return 1; }
    zip="${url##*/}"
    _fm_log "helixsr: downloading $zip"
    echo "fsr-multi: downloading HelixSR $tag (about 200 MB)..."
    if ! scb_fetch "$sumsurl" "$tmp/SHA256SUMS" || ! scb_fetch "$url" "$tmp/$zip"; then
        _fm_log "helixsr: download failed ($url)"; rm -rf "$tmp"; return 1
    fi
    want=$(awk -v f="$zip" '$2==f{print $1}' "$tmp/SHA256SUMS"); got=$(scb_sha "$tmp/$zip")
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        _fm_log "helixsr: checksum mismatch for $zip; not using it"; rm -rf "$tmp"; return 1
    fi
    mkdir "$tmp/x" && scb_unzip_all "$tmp/$zip" "$tmp/x" 2>/dev/null
    src=$(dirname "$(find "$tmp/x" -path '*/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll' -print -quit 2>/dev/null)" 2>/dev/null)
    src=${src%/HLX-FSR4}
    if [ ! -f "$src/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll" ]; then
        _fm_log "helixsr: no HLX-FSR4 DLL in $zip (layout changed?)"; rm -rf "$tmp"; return 1
    fi
    cp -f "$tmp/SHA256SUMS" "$src/.SHA256SUMS" 2>/dev/null
    if mv "$src" "$FSRMULTI_HX_ROOT/$tag"; then
        : >"$stamp"; rm -rf "$tmp"
        _fm_log "helixsr: installed $tag"
    else
        _fm_log "helixsr: couldn't move $tag into $FSRMULTI_HX_ROOT"; rm -rf "$tmp"; return 1
    fi
}

# Build HLX DLSS's network in the background (once per HelixSR version), from the DLSS 310.7.0 DLL that
# Proton-CachyOS already cached in ~/.cache/protonfixes/upscalers (so no NVIDIA download or prompt). Runs
# helixsr-setup.sh --no-fg with stdin closed: every other question is answered no, so it installs into no
# game. Takes several minutes, niced; the DLL shows up as the hlx-dlss entry from the next launch on.
_fm_helixsr_build() {   # dir
    local dir="$1" lock="$1/.fsrmulti-build" nv tmpdll
    [ "$FSRMULTI_HX_BUILD" = 1 ] || return 0
    pgrep -f "$dir/setup/helixsr_setup.py" >/dev/null 2>&1 && return 0
    [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +120 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 0
    nv=$(ls -1 "$HOME"/.cache/protonfixes/upscalers/dlss_v310.7.0.0_*.xz 2>/dev/null | head -n1)
    if [ -z "$nv" ] || ! command -v xz >/dev/null; then
        rmdir "$lock"; _fm_log "hlx-dlss: no cached DLSS 310.7.0.0 (or no xz); run $dir/helixsr-setup.sh by hand"; return 0
    fi
    tmpdll="$dir/.nvngx_dlss.dll"
    if ! xz -dc "$nv" >"$tmpdll" 2>/dev/null || [ ! -s "$tmpdll" ]; then
        rm -f "$tmpdll"; rmdir "$lock"; _fm_log "hlx-dlss: couldn't unpack $nv"; return 0
    fi
    _fm_log "hlx-dlss: building the network in the background (log: $dir/fsr-multi-build.log)"
    ( cd "$dir" && scb_host nice -n 10 setsid ./helixsr-setup.sh --no-fg --dlss "$tmpdll" </dev/null >"$dir/fsr-multi-build.log" 2>&1
      rm -f "$tmpdll"; rmdir "$lock" 2>/dev/null ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# Stage HelixSR's DLLs (newest unpacked version that has HLX FSR 4) into $FSRMULTI_SRC
_fm_helixsr_stage() {
    local d dir="" built
    for d in $(find "$FSRMULTI_HX_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f\n' 2>/dev/null | sort -rV); do
        [ -f "$FSRMULTI_HX_ROOT/$d/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll" ] && { dir="$FSRMULTI_HX_ROOT/$d"; break; }
    done
    [ -n "$dir" ] || return 0
    cmp -s "$dir/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll" "$FSRMULTI_SRC/fsr-hlx-fsr4.dll" 2>/dev/null \
        || cp -f --reflink=auto "$dir/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll" "$FSRMULTI_SRC/fsr-hlx-fsr4.dll"
    # built = differs from the helixsr.dll the ZIP shipped (its hash is in the release's SHA256SUMS)
    built=0
    if [ -f "$dir/HelixSR/helixsr.dll" ] && [ -f "$dir/.SHA256SUMS" ]; then
        want=$(awk '$2=="HelixSR/helixsr.dll"{print $1}' "$dir/.SHA256SUMS")
        [ -n "$want" ] && [ "$(scb_sha "$dir/HelixSR/helixsr.dll")" != "$want" ] && built=1
    fi
    if [ "$built" = 1 ]; then
        cmp -s "$dir/HelixSR/helixsr.dll" "$FSRMULTI_SRC/dlss-hlx-dlss.dll" 2>/dev/null \
            || cp -f --reflink=auto "$dir/HelixSR/helixsr.dll" "$FSRMULTI_SRC/dlss-hlx-dlss.dll"
        [ -f "$dir/HelixSR/helixsr.ini" ] && cp -f "$dir/HelixSR/helixsr.ini" "$FSRMULTI_SRC/dlss-hlx-dlss.ini"
        [ -f "$SCB_CONFIGDIR/helixsr.ini" ] && cp -f "$SCB_CONFIGDIR/helixsr.ini" "$FSRMULTI_SRC/dlss-hlx-dlss.ini"
    else
        rm -f "$FSRMULTI_SRC/dlss-hlx-dlss.dll" "$FSRMULTI_SRC/dlss-hlx-dlss.ini"
        _fm_log "hlx-dlss not built yet: run $dir/helixsr-setup.sh by hand (FSRMULTI_HX_BUILD=1 to automate)"
        _fm_helixsr_build "$dir"
    fi
}

if [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] && [ -n "${PROTON_USE_OPTISCALER:-}" ] && [ "$PROTON_USE_OPTISCALER" != 0 ]; then
    mkdir -p "$FSRMULTI_SRC" 2>/dev/null || true
    if command -v flock >/dev/null && exec {_fm_lockfd}>"$FSRMULTI_SRC/.lock"; then
        flock -w 900 "$_fm_lockfd"
    fi
    [ "$FSRMULTI_CYBOMAN" = 1 ] && _fm_cyboman_update
    if [ "$FSRMULTI_HELIXSR" = 1 ]; then _fm_helixsr_update; _fm_helixsr_stage; fi
    [ -n "${_fm_lockfd:-}" ] && exec {_fm_lockfd}>&-

    # fsr-<name>.dll -> custom/<name>/ffx/, dlss-<name>.dll -> custom/<name>/dlss/ (+ dlss-<name>.ini beside it)
    _fm_n=""
    for f in "$FSRMULTI_SRC"/fsr-*.dll "$FSRMULTI_SRC"/dlss-*.dll; do
        [ -f "$f" ] || continue
        n=${f##*/}
        case "$n" in
            fsr-*) api=ffx; dll=amd_fidelityfx_upscaler_dx12.dll; n=${n#fsr-} ;;
            *) api=dlss; dll=helixsr.dll; n=${n#dlss-} ;;
        esac
        n=${n%.dll}
        d="$FSRMULTI_DST/$n/$api"
        mkdir -p "$d" 2>/dev/null || continue
        cmp -s "$f" "$d/$dll" 2>/dev/null || cp -f --reflink=auto "$f" "$d/$dll" 2>/dev/null || true
        [ -f "${f%.dll}.ini" ] && cp -f "${f%.dll}.ini" "$d/helixsr.ini" 2>/dev/null
        _fm_n+="${_fm_n:+ }$n"
    done
    _fm_log "custom upscalers: ${_fm_n:-none}"
fi

unset -f _fm_log _fm_cyboman_update _fm_helixsr_update _fm_helixsr_build _fm_helixsr_stage
unset _fm_n _fm_lockfd f n d api dll want

scb_guard_end

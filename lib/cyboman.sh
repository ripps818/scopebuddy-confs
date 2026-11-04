# lib/cyboman.sh: logic for cyboman.conf (see that file for settings and modes).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
source "$_scb_lib/cyboman-release.sh"
unset _scb_lib

scb_guard_begin
export LOW_LATENCY_LAYER=1

# --- user settings ---------------------------------------------------------
FSR4_REPO="${FSR4_REPO:-$SCB_DLLS/cyboman-repo}"
FSR4_LOSSY_DIR="${FSR4_LOSSY_DIR:-$FSR4_REPO/prebuilt-lossy}"
FSR4_DUMP_ROOT="${FSR4_DUMP_ROOT:-$SCB_DLLS/cyboman-dump}"
FSR4_DLL_ROOT="${FSR4_DLL_ROOT:-$SCB_DLLS/cyboman}"
FSR4_MODE="${FSR4_MODE:-auto}"
FSR4_SET="${FSR4_SET:-auto}"
FSR4_DLL_BUILD="${FSR4_DLL_BUILD:-exact}"
FSR4_DLL_TARGET="${FSR4_DLL_TARGET:-rx7000}"
FSR4_DLL_TAG="${FSR4_DLL_TAG:-latest}"
FSR4_DLL_CHECK_HOURS="${FSR4_DLL_CHECK_HOURS:-24}"
FSR4_REPO_CHECK_HOURS="${FSR4_REPO_CHECK_HOURS:-24}"
FSR4_KEEP_DESCRIPTOR_HEAP="${FSR4_KEEP_DESCRIPTOR_HEAP:-0}"
FSR4_LOG="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}/cyboman.log"
# ---------------------------------------------------------------------------

_fsr4_appid="${SteamAppId:-${SCB_APPID:-unknown}}"
_fsr4_appid="${_fsr4_appid//\//_}"   # Lutris/Heroic style IDs contain slashes

_fsr4_log() { scb_log "$FSR4_LOG" fsr4 "$*"; }

# Proton maps the Linux root to Z:, so /home/you/x -> Z:/home/you/x
_fsr4_winpath() {
    printf 'Z:%s' "$(realpath -m "$1")"
}

_fsr4_has_spv() {
    compgen -G "$1/*.spv" >/dev/null
}

# Set (or reset to auto) Libraries.FfxDx12SRPath in PROTON_OPTISCALER_CONFIG,
# keeping every other option already in the string.
_fsr4_optiscaler_srpath() {   # value
    local kept="" item items=()
    IFS=';' read -r -a items <<<"${PROTON_OPTISCALER_CONFIG:-}"
    for item in "${items[@]}"; do
        [ -z "$item" ] && continue
        [[ $item == Libraries.FfxDx12SRPath=* ]] && continue
        kept+="${kept:+;}$item"
    done
    PROTON_OPTISCALER_CONFIG="$kept"
    [ -n "$PROTON_OPTISCALER_CONFIG" ] && PROTON_OPTISCALER_CONFIG+=";"
    PROTON_OPTISCALER_CONFIG+="Libraries.FfxDx12SRPath=$1"
    export PROTON_OPTISCALER_CONFIG
}

# Resolve FSR4_DLL_TAG=latest to the newest dll-* release tag, at most once per
# FSR4_DLL_CHECK_HOURS. Prints the tag; falls back to the last one found.
_fsr4_dll_tag() {
    if [ "$FSR4_DLL_TAG" != latest ]; then printf '%s' "$FSR4_DLL_TAG"; return 0; fi
    local cache="$FSR4_DLL_ROOT/latest-tag" tag=""
    if [ -s "$cache" ] && scb_fresh "$cache" "$FSR4_DLL_CHECK_HOURS"; then
        cat "$cache"; return 0
    fi
    tag=$(scb_cyboman_tag)
    if [ -n "$tag" ]; then
        printf '%s\n' "$tag" >"$cache"; printf '%s' "$tag"; return 0
    fi
    [ -s "$cache" ] && { _fsr4_log "couldn't look up the latest release; using cached $(cat "$cache")"; cat "$cache"; return 0; }
    return 1
}

# Keep the shader sets in $FSR4_REPO up to date, at most once per FSR4_REPO_CHECK_HOURS. Failures are
# logged and ignored. With git installed a missing/empty folder becomes a shallow sparse clone (one commit,
# only prebuilt/, prebuilt-lossy/ and tools/), updated by fetching that one commit again; any other git
# clone is git pulled. Without git (or in a folder that already holds a tarball download) the same three
# folders come from GitHub's tarball, which needs only curl and tar. Your own build in override/ is never touched.
_fsr4_repo_update() {
    local gstamp out
    if [ ! -d "$FSR4_REPO/.git" ] && command -v git >/dev/null \
       && { [ ! -e "$FSR4_REPO" ] || [ -z "$(ls -A "$FSR4_REPO" 2>/dev/null)" ]; }; then
        if scb_host timeout 120 git clone -q --depth 1 --filter=blob:none --sparse "$_CYBOMAN_GH.git" "$FSR4_REPO" 2>/dev/null \
           && git -C "$FSR4_REPO" sparse-checkout set prebuilt prebuilt-lossy tools 2>/dev/null \
           && _fsr4_has_spv "$FSR4_REPO/prebuilt"; then
            _fsr4_log "cloned the shader repo (shallow, sparse) ($(git -C "$FSR4_REPO" rev-parse --short HEAD 2>/dev/null))"
            : >"$FSR4_REPO/.git/scb-last-pull"
            return 0
        fi
        _fsr4_log "shallow clone failed; trying the tarball"
        rm -rf "${FSR4_REPO:?}"
    fi
    if [ -d "$FSR4_REPO/.git" ]; then
        command -v git >/dev/null || return 0
        gstamp="$FSR4_REPO/.git/scb-last-pull"
        scb_fresh "$gstamp" "$FSR4_REPO_CHECK_HOURS" && return 0
        if [ "$(git -C "$FSR4_REPO" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
            out=$(scb_host timeout 60 git -C "$FSR4_REPO" fetch -q --depth 1 origin 2>&1 \
                  && scb_host git -C "$FSR4_REPO" reset -q --hard FETCH_HEAD 2>&1)
        else
            out=$(scb_host timeout 30 git -C "$FSR4_REPO" pull --ff-only -q 2>&1)
        fi
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            : >"$gstamp"
            _fsr4_log "repo up to date ($(git -C "$FSR4_REPO" rev-parse --short HEAD 2>/dev/null))"
        else
            _fsr4_log "git update failed, using the repo as is: ${out//$'\n'/ }"
        fi
        return 0
    fi
    command -v tar >/dev/null || return 0
    local stamp="$FSR4_REPO/.scb-checked" shafile="$FSR4_REPO/.scb-sha" sha tmp d
    scb_fresh "$stamp" "$FSR4_REPO_CHECK_HOURS" && return 0
    mkdir -p "$FSR4_REPO" || return 0
    sha=$(scb_get "https://api.github.com/repos/${_CYBOMAN_GH#https://github.com/}/commits/main" "Accept: application/vnd.github.sha" 2>/dev/null)
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || { _fsr4_log "couldn't look up the repo's latest commit; using the repo as is"; return 0; }
    if [ "$(cat "$shafile" 2>/dev/null)" = "$sha" ] && [ -d "$FSR4_REPO/prebuilt" ]; then : >"$stamp"; return 0; fi
    tmp=$(mktemp -d "$FSR4_REPO/.dl.XXXXXX") || return 0
    _fsr4_log "downloading the shader repo ${sha:0:7}"
    if scb_fetch "$_CYBOMAN_GH/archive/$sha.tar.gz" "$tmp/r.tgz" 600 \
       && mkdir "$tmp/x" && scb_host tar -xzf "$tmp/r.tgz" -C "$tmp/x" --strip-components=1 \
            --wildcards '*/prebuilt/*' '*/prebuilt-lossy/*' '*/tools/*' 2>/dev/null \
       && _fsr4_has_spv "$tmp/x/prebuilt"; then
        for d in prebuilt prebuilt-lossy tools; do
            [ -d "$tmp/x/$d" ] && rm -rf "${FSR4_REPO:?}/$d" && mv "$tmp/x/$d" "$FSR4_REPO/$d"
        done
        printf '%s\n' "$sha" >"$shafile"; : >"$stamp"
        _fsr4_log "shader repo up to date (${sha:0:7})"
    else
        _fsr4_log "couldn't download or extract the shader repo; using it as is"
    fi
    rm -rf "$tmp"
}

# Make sure the requested patched DLL is downloaded and verified.
# Sets _fsr4_dll_path on success.
_fsr4_dll_ensure() {
    local build="$FSR4_DLL_BUILD" target="$FSR4_DLL_TARGET" tag dir asset variant member key zipkey tmp sums want got
    case "$build" in
        exact|main) variant=exact ;;
        lossy) variant=lossy ;;
        lossy2) variant=lossy ;;   # lossy2 became "lossy" in dll-2026-10-29
        4.1.2l-exact|4.1.2l-lossy) variant=$build ;;
        *) _fsr4_log "unknown FSR4_DLL_BUILD='$build'"; return 1 ;;
    esac
    asset=$(scb_cyboman_prefix "$target") || { _fsr4_log "unknown FSR4_DLL_TARGET='$target'"; return 1; }
    build="$target-$variant"
    mkdir -p "$FSR4_DLL_ROOT" || return 1

    if [ "$FSR4_DLL_TAG" = latest ]; then dir="$FSR4_DLL_ROOT/$build"
    else dir="$FSR4_DLL_ROOT/$build@$FSR4_DLL_TAG"; fi

    if ! tag=$(_fsr4_dll_tag); then
        if [ -s "$dir/amd_fidelityfx_upscaler_dx12.dll" ]; then
            _fsr4_log "offline; using cached $build DLL ($(cat "$dir/TAG" 2>/dev/null))"
            _fsr4_dll_path="$dir/amd_fidelityfx_upscaler_dx12.dll"; return 0
        fi
        _fsr4_log "couldn't find a dll-* release tag (no git and no network?)"; return 1
    fi

    # Already have this tag?
    if [ -s "$dir/amd_fidelityfx_upscaler_dx12.dll" ] && [ "$(cat "$dir/TAG" 2>/dev/null)" = "$tag" ]; then
        _fsr4_dll_path="$dir/amd_fidelityfx_upscaler_dx12.dll"; return 0
    fi

    # Download, verify against the release's SHA256SUMS, then swap in atomically.
    # On any failure, keep using the previously downloaded DLL if there is one.
    _fsr4_dll_fail() {
        _fsr4_log "$1"; [ -n "${tmp:-}" ] && rm -rf "$tmp"
        if [ -s "$dir/amd_fidelityfx_upscaler_dx12.dll" ]; then
            _fsr4_log "keeping cached $build DLL ($(cat "$dir/TAG" 2>/dev/null))"
            _fsr4_dll_path="$dir/amd_fidelityfx_upscaler_dx12.dll"; return 0
        fi
        return 1
    }
    tmp=$(mktemp -d "$FSR4_DLL_ROOT/.dl.XXXXXX") || { tmp=""; _fsr4_dll_fail "couldn't create a temp dir in $FSR4_DLL_ROOT"; return; }
    sums="$tmp/SHA256SUMS"
    member="$variant/amd_fidelityfx_upscaler_dx12.dll"
    key="$target/$member"
    if ! scb_fetch "$_CYBOMAN_GH/releases/download/$tag/SHA256SUMS" "$sums"; then
        _fsr4_dll_fail "download failed ($tag/SHA256SUMS)"; return
    fi
    # The zip name carries the release date (fsr4.1.1-cyboman-rx7000-2026-10-22.zip).
    asset=$(scb_cyboman_asset "$sums" "$asset")
    zipkey="$asset"
    _fsr4_log "downloading $asset from release $tag"
    if [ -z "$asset" ] || ! scb_fetch "$_CYBOMAN_GH/releases/download/$tag/$asset" "$tmp/$asset"; then
        _fsr4_dll_fail "download failed ($tag/$asset)"; return
    fi
    if [ -n "$zipkey" ]; then
        want=$(awk -v f="$zipkey" '$2==f{print $1}' "$sums")
        got=$(scb_sha "$tmp/$asset")
        if [ -z "$want" ] || [ "$want" != "$got" ]; then
            _fsr4_dll_fail "checksum mismatch for $asset; not using it"; return
        fi
        if ! scb_unzip_one "$tmp/$asset" "$member" "$tmp/amd_fidelityfx_upscaler_dx12.dll"; then
            _fsr4_dll_fail "couldn't extract $asset (need unzip, bsdtar or python3)"; return
        fi
    fi
    want=$(awk -v f="$key" '$2==f{print $1}' "$sums")
    got=$(scb_sha "$tmp/amd_fidelityfx_upscaler_dx12.dll")
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        _fsr4_dll_fail "checksum mismatch for $key; not using it"; return
    fi
    mkdir -p "$dir"
    mv -f "$tmp/amd_fidelityfx_upscaler_dx12.dll" "$dir/amd_fidelityfx_upscaler_dx12.dll"
    printf '%s\n' "$tag" >"$dir/TAG"
    rm -rf "$tmp"
    _fsr4_log "installed $build DLL from $tag (sha256 ok)"
    _fsr4_dll_path="$dir/amd_fidelityfx_upscaler_dx12.dll"
}

# The overrides match AMD's original shaders only. With the repo's patched DLL
# (or another modified one) in the game folder they silently do nothing, and a
# dump would capture the wrong shaders. Released patched DLLs carry "cyboman" in
# their version name and/or a ".fsr4" PE section, so warn if one is found.
_fsr4_check_dll() {
    declare -F SCB_GetGameDir >/dev/null || return 0
    [ -n "${command:-}" ] || return 0
    local gamedir dll
    gamedir=$(SCB_GetGameDir "$command" 2>/dev/null) || return 0
    [ -d "$gamedir" ] || return 0
    while IFS= read -r dll; do
        if grep -aq 'cyboman' "$dll" 2>/dev/null || head -c 4096 "$dll" | grep -aq '\.fsr4'; then
            _fsr4_log "WARNING: $dll is a PATCHED FSR DLL; overrides/dumps need AMD's original (restore the .orig)"
        fi
    done < <(find "$gamedir" -maxdepth 3 -iname 'amd_fidelityfx_upscaler_dx12.dll' 2>/dev/null)
}

# Remove one item from a comma-separated list, keep the rest (pure bash).
_fsr4_list_remove() {   # list item
    local out="" x items=()
    IFS=',' read -r -a items <<<"$1"
    for x in "${items[@]}"; do
        [ -z "$x" ] || [ "$x" = "$2" ] || out+="${out:+,}$x"
    done
    printf '%s' "$out"
}

# Never let a leftover var from the environment or scb.conf leak into this mode
unset VKD3D_SHADER_DUMP_PATH VKD3D_SHADER_OVERRIDE

_fsr4_mode="$FSR4_MODE"
_fsr4_auto=0
# PROTON_USE_OPTISCALER can name an FSR 4 version (e.g. 4.0.2). The patched DLL and
# shaders are 4.1.1 only, so for any other explicit version do nothing.
case "${PROTON_USE_OPTISCALER:-}" in
    4.1.1*|4.1.2*|[!0-9]*|"") ;;
    [0-9]*.[0-9]*)
        case "$_fsr4_mode" in
            auto|dll|override)
                _fsr4_log "PROTON_USE_OPTISCALER=$PROTON_USE_OPTISCALER is not FSR 4.1.1; running stock shaders"
                _fsr4_mode=stock ;;
        esac ;;
esac
if [ "$_fsr4_mode" = auto ]; then
    _fsr4_auto=1
    if scb_opti_on; then _fsr4_mode=dll; else _fsr4_mode=override; fi
fi
_fsr4_marker="$FSR4_DLL_ROOT/state/$_fsr4_appid"

# ---- dll mode (falls back to override if it can't be used) ----------------
if [ "$_fsr4_mode" = dll ]; then
    if ! scb_opti_on; then
        _fsr4_log "dll mode needs Proton's OptiScaler (PROTON_USE_OPTISCALER=1 or =nightly, set above the source line); running stock shaders"
        _fsr4_mode=stock
    else
        if command -v flock >/dev/null && mkdir -p "$FSR4_DLL_ROOT" && exec {_fsr4_lockfd}>"$FSR4_DLL_ROOT/.lock"; then
            flock -w 300 "$_fsr4_lockfd"
        fi
        if _fsr4_dll_ensure; then
            _fsr4_winp=$(_fsr4_winpath "$_fsr4_dll_path"); _fsr4_winp="${_fsr4_winp//\//\\}"
            _fsr4_optiscaler_srpath "$_fsr4_winp"
            mkdir -p "${_fsr4_marker%/*}" && : >"$_fsr4_marker"
            _fsr4_log "dll ($FSR4_DLL_TARGET/$FSR4_DLL_BUILD, $(cat "${_fsr4_dll_path%/*}/TAG" 2>/dev/null)) -> PROTON_OPTISCALER_CONFIG=$PROTON_OPTISCALER_CONFIG"
            case "$FSR4_DLL_BUILD" in lossy*) _fsr4_log "note: LOSSY build in use, image differs from AMD's" ;; esac
        else
            if [ "$_fsr4_auto" = 1 ]; then
                _fsr4_log "no usable patched DLL; auto mode falling back to override"
                _fsr4_mode=override
            else
                _fsr4_log "no usable patched DLL; running stock shaders"
                _fsr4_mode=stock
            fi
        fi
        [ -n "${_fsr4_lockfd:-}" ] && exec {_fsr4_lockfd}>&-
    fi
fi

# Leaving dll mode: the ini setting written by PROTON_OPTISCALER_CONFIG is
# permanent, so point OptiScaler back at its own DLL. Otherwise the overrides
# would silently match nothing.
if [ "$_fsr4_mode" != dll ] && [ -e "$_fsr4_marker" ] && scb_opti_on; then
    _fsr4_optiscaler_srpath auto
    rm -f "$_fsr4_marker"
    _fsr4_log "reset Libraries.FfxDx12SRPath=auto (was set by dll mode)"
fi

# Strip descriptor_heap from VKD3D_CONFIG (e.g. set globally in scb.conf) for the
# shader-override modes; dumps must be made with the same setting as override runs.
if [ "$_fsr4_mode" = override ] || [ "$_fsr4_mode" = dump ]; then
    if [ "$FSR4_KEEP_DESCRIPTOR_HEAP" != 1 ] && [[ ",${VKD3D_CONFIG:-}," == *,descriptor_heap,* ]]; then
        VKD3D_CONFIG=$(_fsr4_list_remove "$VKD3D_CONFIG" descriptor_heap)
        if [ -n "$VKD3D_CONFIG" ]; then export VKD3D_CONFIG; else unset VKD3D_CONFIG; fi
        _fsr4_log "removed descriptor_heap from VKD3D_CONFIG (now '${VKD3D_CONFIG:-}'); set FSR4_KEEP_DESCRIPTOR_HEAP=1 to keep it"
    fi
fi

case "$_fsr4_mode" in
    dll) ;;   # handled above
    stock) ;; # dll mode couldn't be used; already logged
    override)
        _fsr4_repo_update
        # The overrides only match AMD's original 4.1.1 DLL; make Proton supply it.
        export PROTON_FSR4_UPGRADE="${PROTON_FSR4_UPGRADE:-1}"
        _fsr4_log "override mode: PROTON_FSR4_UPGRADE=$PROTON_FSR4_UPGRADE"
        _fsr4_prebuilt="$FSR4_REPO/prebuilt"
        _fsr4_own="$FSR4_REPO/override"
        if [ -n "${FSR4_OVERRIDE_DIR:-}" ]; then
            _fsr4_dir="$FSR4_OVERRIDE_DIR"
        else
            case "$FSR4_SET" in
                prebuilt) _fsr4_dir="$_fsr4_prebuilt" ;;
                own)      _fsr4_dir="$_fsr4_own" ;;
                lossy)    _fsr4_dir="$FSR4_LOSSY_DIR" ;;
                auto)
                    # Your own build wins and is used alone. Don't mix in prebuilt/:
                    # if you needed your own build, prebuilt/ doesn't fit your setup.
                    if _fsr4_has_spv "$_fsr4_own"; then _fsr4_dir="$_fsr4_own"
                    else _fsr4_dir="$_fsr4_prebuilt"; fi
                    ;;
                *)  _fsr4_log "unknown FSR4_SET='$FSR4_SET' (use auto|prebuilt|own|lossy)" ;;
            esac
        fi
        # prebuilt/ and lossy were translated without descriptor_heap; with it the
        # driver can crash compiling them (seen: FF16, Proton-Wineland, RADV).
        if [[ ",${VKD3D_CONFIG:-}," == *,descriptor_heap,* ]] && [ -z "${FSR4_OVERRIDE_DIR:-}" ] \
           && { [ "${_fsr4_dir:-}" = "$_fsr4_prebuilt" ] || [ "${_fsr4_dir:-}" = "$FSR4_LOSSY_DIR" ]; }; then
            _fsr4_log "VKD3D_CONFIG has descriptor_heap (FSR4_KEEP_DESCRIPTOR_HEAP=1): not using '$_fsr4_dir' (doesn't fit, can crash the driver); running stock shaders. Build your own (FSR4_MODE=dump + build_override.sh) or use FSR4_MODE=dll"
            _fsr4_dir=""
        elif [ -n "${_fsr4_dir:-}" ] && _fsr4_has_spv "$_fsr4_dir"; then
            export VKD3D_SHADER_OVERRIDE="$(_fsr4_winpath "$_fsr4_dir")"
            if [ -n "${FSR4_OVERRIDE_DIR:-}" ]; then _fsr4_label=FSR4_OVERRIDE_DIR; else _fsr4_label=$FSR4_SET; fi
            _fsr4_log "override ($_fsr4_label) -> $VKD3D_SHADER_OVERRIDE"
            [ "$_fsr4_dir" = "$FSR4_LOSSY_DIR" ] && _fsr4_log "note: LOSSY set in use, image differs from AMD's"
            _fsr4_check_dll
        elif [ -n "${_fsr4_dir:-}" ]; then
            _fsr4_log "no .spv files in '$_fsr4_dir'; running stock FSR shaders (check FSR4_REPO / FSR4_SET)"
        fi
        ;;
    dump)
        _fsr4_dir="$FSR4_DUMP_ROOT/$_fsr4_appid"
        mkdir -p "$_fsr4_dir"
        if [ -n "$(ls -A "$_fsr4_dir" 2>/dev/null)" ]; then
            _fsr4_log "WARNING: dump dir $_fsr4_dir is not empty; new shaders will be mixed with old ones"
        fi
        export VKD3D_SHADER_DUMP_PATH="$(_fsr4_winpath "$_fsr4_dir")"
        _fsr4_log "dump -> $VKD3D_SHADER_DUMP_PATH (FSR 4 on at your usual resolution/preset, get into gameplay, quit)"
        _fsr4_log "then: cd '$FSR4_REPO/tools' && ./check_prebuilt.sh '$_fsr4_dir'  (if it differs: ./build_override.sh '$_fsr4_dir')"
        _fsr4_check_dll
        ;;
    off)
        _fsr4_log "disabled"
        ;;
    *)
        _fsr4_log "unknown FSR4_MODE='$FSR4_MODE' (use auto|override|dll|dump|off); doing nothing"
        ;;
esac

# The repo warns that RADV_PERFTEST=cswave32 adds ~1.1 ms to FSR 4; drop it if set.
if [ "$_fsr4_mode" != off ] && [[ ",${RADV_PERFTEST:-}," == *,cswave32,* ]]; then
    RADV_PERFTEST=$(_fsr4_list_remove "$RADV_PERFTEST" cswave32)
    if [ -n "$RADV_PERFTEST" ]; then export RADV_PERFTEST; else unset RADV_PERFTEST; fi
    _fsr4_log "removed cswave32 from RADV_PERFTEST (slows FSR 4)"
fi

unset -f _fsr4_repo_update _fsr4_list_remove _fsr4_log _fsr4_winpath _fsr4_has_spv _fsr4_check_dll \
         _fsr4_optiscaler_srpath _fsr4_dll_tag _fsr4_dll_ensure _fsr4_dll_fail
unset _fsr4_appid _fsr4_dir _fsr4_prebuilt _fsr4_own _fsr4_label \
      _fsr4_mode _fsr4_marker _fsr4_auto _fsr4_dll_path _fsr4_winp _fsr4_lockfd

scb_guard_end

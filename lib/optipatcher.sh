# lib/optipatcher.sh: OptiPatcher periodic update + prefix install.
# Sourced by scb.conf when PROTON_USE_OPTISCALER is set. Nothing here may stop the game from
# launching: ScopeBuddy runs configs under set -e, so every step that can fail is guarded.
#
# Per-game off switch (launch options, before scopebuddy): SCB_NO_OPTIPATCHER=1. It also removes a
# copy put in that prefix earlier, and the AMDNR tool honours it too. The shared OptiPatcher.asi
# still gets updated, since other games use it.
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

OPTIPATCHER_DIR="$SCB_DLLS/optipatcher"
OPTIPATCHER_SRC="$OPTIPATCHER_DIR/OptiPatcher.asi"
STAMP_FILE="$OPTIPATCHER_DIR/.last_check"
CHECK_INTERVAL=$((6 * 3600))   # seconds between update checks

mkdir -p "$OPTIPATCHER_DIR" || true
now=$(date +%s)
last_check=0
[ -f "$STAMP_FILE" ] && last_check=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
[[ "$last_check" =~ ^[0-9]+$ ]] || last_check=0

if [ $((now - last_check)) -ge "$CHECK_INTERVAL" ]; then
    asset_url=$(curl -sf --max-time 2 \
        "https://api.github.com/repos/optiscaler/OptiPatcher/releases/tags/rolling" \
        | grep -o '"browser_download_url": *"[^"]*"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -i '\.asi$' | head -n1) || true

    if [ -n "${asset_url:-}" ]; then
        # same folder as the target, so the mv below is an atomic rename (the AMDNR tool and
        # other games read OptiPatcher.asi from here)
        tmp_file=$(mktemp -p "$OPTIPATCHER_DIR" .OptiPatcher.XXXXXX) || tmp_file=""
        if [ -n "$tmp_file" ]; then
            if curl -sfL --max-time 5 -o "$tmp_file" "$asset_url"; then
                if ! cmp -s "$tmp_file" "$OPTIPATCHER_SRC" 2>/dev/null; then
                    mv -f "$tmp_file" "$OPTIPATCHER_SRC" || rm -f "$tmp_file"
                else
                    rm -f "$tmp_file"
                fi
            else
                rm -f "$tmp_file"
            fi
        fi
    fi
    echo "$now" > "$STAMP_FILE" 2>/dev/null || true
fi

# --- install into prefix (or take it out again when switched off for this game) ---
# Installed as OptiPatcher-rolling.asi: Proton-CachyOS's nightly handling removes a file named
# OptiPatcher.asi from umu/plugins on launch (its package brings its own OptiPatcher). A plain
# OptiPatcher.asi left there is removed so two copies never load.
UMU_DIR="${STEAM_COMPAT_DATA_PATH:-}/pfx/drive_c/windows/system32/umu"
OPTIPATCHER_NAME="OptiPatcher-rolling.asi"
if [ "${SCB_NO_OPTIPATCHER:-0}" = 1 ]; then
    # every place a copy can be: ours, and Proton's in either layout
    [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] &&
        rm -f "$UMU_DIR/plugins/$OPTIPATCHER_NAME" "$UMU_DIR/plugins/OptiPatcher.asi" \
              "$UMU_DIR/OptiScaler/plugins/OptiPatcher.asi" 2>/dev/null || true
elif [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] && [ -f "$OPTIPATCHER_SRC" ]; then
    rm -f "$UMU_DIR/plugins/OptiPatcher.asi" 2>/dev/null || true
    if mkdir -p "$UMU_DIR/plugins" &&
        { cmp -s "$OPTIPATCHER_SRC" "$UMU_DIR/plugins/$OPTIPATCHER_NAME" 2>/dev/null ||
          cp -f "$OPTIPATCHER_SRC" "$UMU_DIR/plugins/$OPTIPATCHER_NAME"; }; then
        # Proton rewrites OptiScaler.ini when it installs/upgrades OptiScaler (every
        # nightly), undoing sed edits, so set these via PROTON_OPTISCALER_CONFIG instead.
        # The plugin folder is spelled out because OptiScaler otherwise derives it from OptiDllPath
        # or the game's folder: stable as packaged for Proton lands on umu\plugins, but the v10
        # nightly layout looks in an OptiScaler\ subfolder instead. Other plugin confs
        # (mfgunlocker.conf) use the same umu\plugins folder.
        PROTON_OPTISCALER_CONFIG="${PROTON_OPTISCALER_CONFIG:+$PROTON_OPTISCALER_CONFIG;}Plugins.LoadAsiPlugins=true;Plugins.Path=c:\\windows\\system32\\umu\\plugins"
        export PROTON_OPTISCALER_CONFIG
    fi
fi

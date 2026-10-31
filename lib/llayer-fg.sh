# lib/llayer-fg.sh: logic for llayer-fg.conf (see that file for usage).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

_llfg_build="$HOME/Projects/llayer-build/out"
_llfg_dir="$SCB_DLLS/low-latency-layer-fg"
if [ "${LLAYER_FG:-on}" != off ] && [ -f "$_llfg_build/libVkLayer_KORTHOS_LowLatency.so" ]; then
    mkdir -p "$_llfg_dir" 2>/dev/null
    cmp -s "$_llfg_build/libVkLayer_KORTHOS_LowLatency.so" "$_llfg_dir/libVkLayer_KORTHOS_LowLatency.so" 2>/dev/null \
        || cp -f "$_llfg_build/libVkLayer_KORTHOS_LowLatency.so" "$_llfg_dir/libVkLayer_KORTHOS_LowLatency.so" 2>/dev/null
    sed "s|\"library_path\": *\"[^\"]*\"|\"library_path\": \"$_llfg_dir/libVkLayer_KORTHOS_LowLatency.so\"|" \
        "$_llfg_build/low_latency_layer.json" >"$_llfg_dir/low_latency_layer.json.new" 2>/dev/null \
        && mv -f "$_llfg_dir/low_latency_layer.json.new" "$_llfg_dir/low_latency_layer.json"
    if [ -f "$_llfg_dir/low_latency_layer.json" ]; then
        export VK_ADD_IMPLICIT_LAYER_PATH="$_llfg_dir${VK_ADD_IMPLICIT_LAYER_PATH:+:$VK_ADD_IMPLICIT_LAYER_PATH}"
        export LOW_LATENCY_LAYER=1
        [ "${LLAYER_FG_PACING:-1}" = 1 ] && export LOW_LATENCY_LAYER_FRAMEGEN_PACING=1
    fi
fi
unset _llfg_build _llfg_dir
true

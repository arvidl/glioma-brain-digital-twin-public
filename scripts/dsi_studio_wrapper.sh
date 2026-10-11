#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# dsi_studio wrapper — bridges the .src.gz.sz vs .src.gz naming mismatch
#
# DSI Studio "Hou" (2025+) saves SRC files with a .sz suffix, e.g.
#   output.src.gz.sz
# but QSIPrep 1.1.x expects the classic .src.gz name.
#
# This wrapper:
#   1. Calls the real dsi_studio binary
#   2. If --action=src, renames any .src.gz.sz → .src.gz so QSIPrep finds it
# ---------------------------------------------------------------------------

# Locate the real DSI Studio binary (skip this wrapper in PATH)
SELF="$(realpath "$0")"
REAL_DSI=""
IFS=: read -ra DIRS <<< "$PATH"
for dir in "${DIRS[@]}"; do
    candidate="${dir}/dsi_studio"
    if [[ -x "$candidate" ]] && [[ "$(realpath "$candidate")" != "$SELF" ]]; then
        REAL_DSI="$candidate"
        break
    fi
done

if [[ -z "$REAL_DSI" ]]; then
    echo "ERROR: dsi_studio_wrapper could not find real dsi_studio binary" >&2
    exit 1
fi

# Parse --output and --action from command-line args
ACTION=""
OUTPUT=""
for arg in "$@"; do
    case "$arg" in
        --action=*) ACTION="${arg#--action=}" ;;
        --output=*) OUTPUT="${arg#--output=}" ;;
    esac
done

# Run the real binary, passing all arguments through
"$REAL_DSI" "$@"
EXIT_CODE=$?

# If this was a src action and the .sz file exists but the expected file doesn't,
# rename it so QSIPrep can find it.
if [[ "$ACTION" == "src" && -n "$OUTPUT" ]]; then
    SZ_FILE="${OUTPUT}.sz"
    if [[ -f "$SZ_FILE" && ! -f "$OUTPUT" ]]; then
        mv "$SZ_FILE" "$OUTPUT"
        echo "[dsi_studio_wrapper] Renamed ${SZ_FILE} → ${OUTPUT}"
    fi
fi

exit $EXIT_CODE

#!/bin/bash
# Everything `godot --export-debug "Android"` needs on a fresh cloud session,
# in about a minute. See docs/SHELL.md "Building the APK" for why each piece
# is what it is. Idempotent: re-running skips what is already there.
#
#   tools/setup_android_export.sh && mkdir -p build && \
#     godot --headless --path . --export-debug "Android" build/tender.apk
set -euo pipefail

GODOT_VERSION="4.7.1"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
SDK="${ANDROID_SDK_STUB:-/opt/android-sdk}"
KS="$HOME/.local/share/godot/keystores/debug.keystore"
CFG="$HOME/.config/godot/editor_settings-4.7.tres"

# 1. the debug template: the FIRST member of the 1.22 GB .tpz, so a byte-range
#    fetch of its local header + data and one raw inflate is enough
if [ ! -s "$TPL_DIR/android_debug.apk" ]; then
  mkdir -p "$TPL_DIR"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -sSL --retry 3 -r 0-125820715 -o "$TMP/dbg.bin" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  python3 - "$TMP/dbg.bin" "$TPL_DIR/android_debug.apk" <<'PY'
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
sig, _, _, comp, _, _, _, csize, usize, nlen, elen = struct.unpack("<IHHHHHIIIHH", d[:30])
name = d[30:30 + nlen].decode()
assert sig == 0x04034b50 and comp == 8 and name == "templates/android_debug.apk", (hex(sig), comp, name)
raw = zlib.decompressobj(-15).decompress(d[30 + nlen + elen:])
assert len(raw) == usize, (len(raw), usize)
open(sys.argv[2], "wb").write(raw)
PY
fi

# 2. apksigner: Ubuntu packages the real one (dl.google.com is blocked here)
command -v apksigner >/dev/null || { apt-get update -qq; apt-get install -y -qq apksigner; }

# 3. an SDK-shaped directory: Godot checks that adb exists and runs
#    build-tools/<ver>/apksigner; 36.0.0 matches its default target SDK
mkdir -p "$SDK/platform-tools" "$SDK/build-tools/36.0.0"
[ -x "$SDK/platform-tools/adb" ] || { printf '#!/bin/bash\nexit 0\n' > "$SDK/platform-tools/adb"; chmod +x "$SDK/platform-tools/adb"; }
ln -sf "$(command -v apksigner)" "$SDK/build-tools/36.0.0/apksigner"

# 4. a debug keystore (a NEW key per container: an APK built here will not
#    install over one signed by an earlier session's key - uninstall first)
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

# 5. point the editor settings at all of it
if [ ! -f "$CFG" ]; then
  mkdir -p "$(dirname "$CFG")"
  JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  cat > "$CFG" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME_DIR"
export/android/android_sdk_path = "$SDK"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
TRES
fi
echo "android export ready"

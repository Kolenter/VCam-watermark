#!/bin/bash
# VCam watermark patch (macOS)
#   sudo bash macos/apply.sh
set -e

APP="/Applications/VCam/VCam.app"
FE_DIR="$APP/Contents/Resources/frontend"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
ENT="$DIR/entitlements-sign.plist"
ORIG_DIR="$ROOT/originals"

if [ ! -d "$FE_DIR" ]; then
  echo "ERROR: VCam not found at $APP" >&2
  exit 1
fi

JS=$(grep -l "changeWatermarkPath" "$FE_DIR"/App-*.js 2>/dev/null | head -1)
if [ -z "$JS" ]; then
  echo "ERROR: no App-*.js with changeWatermarkPath. Bundle layout changed - see README.md." >&2
  exit 1
fi
echo "[1/5] target: $(basename "$JS")"

STAMP=$(date +%Y%m%d-%H%M%S)
BK="$ORIG_DIR/$(basename "$JS").$STAMP.orig"
mkdir -p "$ORIG_DIR"
cp "$JS" "$BK"
echo "[2/5] backup: $BK"

python3 - "$JS" << 'PYEOF'
import sys, re
path = sys.argv[1]
data = open(path, 'r', encoding='utf-8').read()

key = 'changeWatermarkPath'
idx = data.find(key)
if idx == -1:
    print("ERROR: changeWatermarkPath not found"); sys.exit(1)

brace = data.find('{', idx)
if brace == -1:
    print("ERROR: function body not found"); sys.exit(1)

depth = 0
end = None
for i in range(brace, len(data)):
    c = data[i]
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    print("ERROR: unbalanced braces"); sys.exit(1)

old = data[idx:end]
pm = re.match(r'changeWatermarkPath\(([^)]*)\)', old)
param = pm.group(1) if pm else 'e'
new = f'changeWatermarkPath({param}){{this.watermarkBuffer=void 0,this.watermarkMimeType=void 0}}'

if old == new:
    print("already patched, skip"); sys.exit(0)

data2 = data[:idx] + new + data[end:]
open(path, 'w', encoding='utf-8').write(data2)
print(f"[3/5] patched. delta bytes: {len(data2)-len(data)}")
print(f"       was:  {old[:90]}...")
print(f"       now:  {new}")
PYEOF

echo "[4/5] re-signing VCam.app (ad-hoc)..."
codesign --force --sign - --entitlements "$ENT" "$APP"

echo "[5/5] verify signature..."
codesign --verify --verbose "$APP" 2>&1 | head -3

echo
echo "DONE. Restart VCam - watermark should be gone."
echo "Rollback: see README.md (originals/ or reinstall)."

#!/bin/bash
set -euo pipefail

# normalize-app.sh — Normalize an unsigned .app bundle for reproducible comparison.
# Zeros non-deterministic metadata (UUIDs, timestamps, build-machine info, code
# signatures, temp paths) so that two builds from the same source produce identical
# normalized output.
#
# Usage: ./scripts/normalize-app.sh <path/to/birch.app>
#
# Operates in-place on the .app bundle. Make a copy first if you need the original.

APP_PATH="${1:?Usage: normalize-app.sh <path/to/birch.app>}"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH is not a directory" >&2
  exit 1
fi

echo "==> Normalizing: $APP_PATH"

# ---------------------------------------------------------------------------
# 1. Canonicalize Assets.car files
#    Replace binary .car with sorted JSON dump (content-equivalent, order-
#    independent). Must happen BEFORE any binary zeroing that would corrupt
#    the BOM header.
# ---------------------------------------------------------------------------
echo "  - Canonicalizing Assets.car..."
find "$APP_PATH" -name "Assets.car" -type f | while read -r car_file; do
  json_file="${car_file}.json"
  if xcrun assetutil --info "$car_file" > "$json_file" 2>/dev/null; then
    # Sort JSON keys and strip non-deterministic fields for canonical representation
    python3 << PYEOF
import json

path = """$json_file"""
with open(path) as f:
    data = json.load(f)

def strip_timestamps(obj):
    if isinstance(obj, dict):
        return {k: strip_timestamps(v) for k, v in obj.items()
                if k not in ("Timestamp",)}
    elif isinstance(obj, list):
        return [strip_timestamps(item) for item in obj]
    return obj

data = strip_timestamps(data)

# Sort the list of asset entries by a stable key
if isinstance(data, list):
    data.sort(key=lambda x: json.dumps(x, sort_keys=True))

with open(path, 'w') as f:
    json.dump(data, f, sort_keys=True, indent=2)
PYEOF
    # Replace .car with canonical JSON
    mv "$json_file" "$car_file"
  else
    rm -f "$json_file"
    echo "    Warning: assetutil failed for $car_file, zeroing known variable fields instead"
    # Fallback: zero the BOM tree ordering section
    python3 << PYEOF
import struct

path = """$car_file"""
with open(path, 'rb') as f:
    data = bytearray(f.read())

# Zero BOM tree metadata at known offsets
# BOM header timestamp (offset 0x18)
if len(data) > 0x1C:
    struct.pack_into('<I', data, 0x18, 0)

with open(path, 'wb') as f:
    f.write(data)
PYEOF
  fi
done

# ---------------------------------------------------------------------------
# 2. Strip code signatures from all Mach-O binaries
#    Ad-hoc signatures are non-deterministic. Must be done before other
#    Mach-O modifications to avoid signature-related size differences.
# ---------------------------------------------------------------------------
echo "  - Stripping code signatures from Mach-O binaries..."
find "$APP_PATH" -type f | while read -r file; do
  if file "$file" | grep -q "Mach-O"; then
    codesign --remove-signature "$file" 2>/dev/null || true
  fi
done

# ---------------------------------------------------------------------------
# 3. Zero LC_UUID in all Mach-O binaries
# ---------------------------------------------------------------------------
echo "  - Zeroing LC_UUID in Mach-O binaries..."
find "$APP_PATH" -type f | while read -r file; do
  if file "$file" | grep -q "Mach-O"; then
    python3 << PYEOF
import struct, sys

path = """$file"""
with open(path, 'rb') as f:
    data = bytearray(f.read())

def get_slice_offsets(data):
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic in (0xCAFEBABE, 0xBEBAFECA):
        nfat = struct.unpack_from('>I', data, 4)[0]
        return [struct.unpack_from('>I', data, 8 + i * 20 + 8)[0] for i in range(nfat)]
    elif magic in (0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE):
        return [0]
    return []

def zero_uuids(data, base):
    m = struct.unpack_from('<I', data, base)[0]
    if m in (0xFEEDFACF, 0xCFFAEDFE):
        hdr_size = 32
    elif m in (0xFEEDFACE, 0xCEFAEDFE):
        hdr_size = 28
    else:
        return
    ncmds = struct.unpack_from('<I', data, base + 16)[0]
    pos = base + hdr_size
    for _ in range(ncmds):
        if pos + 8 > len(data):
            break
        cmd = struct.unpack_from('<I', data, pos)[0]
        cmdsize = struct.unpack_from('<I', data, pos + 4)[0]
        if cmdsize == 0:
            break
        if cmd == 0x1B:  # LC_UUID
            for j in range(16):
                data[pos + 8 + j] = 0
        pos += cmdsize

for base in get_slice_offsets(data):
    zero_uuids(data, base)

with open(path, 'wb') as f:
    f.write(data)
PYEOF
  fi
done

# ---------------------------------------------------------------------------
# 4. Zero Mach-O timestamps in load commands
# ---------------------------------------------------------------------------
echo "  - Zeroing Mach-O timestamps..."
find "$APP_PATH" -type f | while read -r file; do
  if file "$file" | grep -q "Mach-O"; then
    python3 << PYEOF
import struct

path = """$file"""
with open(path, 'rb') as f:
    data = bytearray(f.read())

def get_slice_offsets(data):
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic in (0xCAFEBABE, 0xBEBAFECA):
        nfat = struct.unpack_from('>I', data, 4)[0]
        return [struct.unpack_from('>I', data, 8 + i * 20 + 8)[0] for i in range(nfat)]
    elif magic in (0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE):
        return [0]
    return []

for base in get_slice_offsets(data):
    m = struct.unpack_from('<I', data, base)[0]
    if m in (0xFEEDFACF, 0xCFFAEDFE):
        hdr_size = 32
    elif m in (0xFEEDFACE, 0xCEFAEDFE):
        hdr_size = 28
    else:
        continue
    ncmds = struct.unpack_from('<I', data, base + 16)[0]
    pos = base + hdr_size
    for _ in range(ncmds):
        if pos + 8 > len(data):
            break
        cmd = struct.unpack_from('<I', data, pos)[0]
        cmdsize = struct.unpack_from('<I', data, pos + 4)[0]
        if cmdsize == 0:
            break
        # LC_ID_DYLIB (0xD), LC_LOAD_DYLIB (0xC), LC_LOAD_WEAK_DYLIB (0x80000018)
        if cmd in (0xC, 0xD, 0x80000018):
            struct.pack_into('<I', data, pos + 16, 0)
        pos += cmdsize

with open(path, 'wb') as f:
    f.write(data)
PYEOF
  fi
done

# ---------------------------------------------------------------------------
# 5. Zero non-deterministic temp paths in Mach-O string tables
#    Xcode embeds random temp paths like swbuild.tmp.XXXXXXXX when injecting
#    stub binaries into codeless frameworks.
# ---------------------------------------------------------------------------
echo "  - Zeroing non-deterministic temp paths in Mach-O binaries..."
find "$APP_PATH" -type f | while read -r file; do
  if file "$file" | grep -q "Mach-O"; then
    python3 << PYEOF
import re

path = """$file"""
with open(path, 'rb') as f:
    data = bytearray(f.read())

# Replace random temp directory names: swbuild.tmp.XXXXXXXX
# The 8 chars after 'swbuild.tmp.' are random alphanumeric
pattern = b'swbuild.tmp.'
i = 0
while i < len(data) - 20:
    pos = data.find(pattern, i)
    if pos == -1:
        break
    # Zero the 8 random characters after the pattern
    start = pos + len(pattern)
    for j in range(8):
        if start + j < len(data):
            data[start + j] = 0
    i = pos + 1

# Also zero /var/folders random paths (DerivedData-like paths)
# Pattern: /var/folders/XX/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/
pattern2 = b'/var/folders/'
i = 0
while i < len(data) - 60:
    pos = data.find(pattern2, i)
    if pos == -1:
        break
    # Zero from /var/folders/ to the next null byte or path separator after T/
    end = pos + len(pattern2)
    while end < len(data) and data[end] != 0:
        end += 1
    for j in range(pos, end):
        data[j] = 0
    i = pos + 1

with open(path, 'wb') as f:
    f.write(data)
PYEOF
  fi
done

# ---------------------------------------------------------------------------
# 6. Strip build-machine metadata from Info.plist
# ---------------------------------------------------------------------------
echo "  - Stripping build-machine metadata from Info.plist..."
INFO_PLIST="$APP_PATH/Info.plist"
if [ -f "$INFO_PLIST" ]; then
  KEYS_TO_REMOVE=(
    DTXcodeBuild
    DTCompiler
    BuildMachineOSBuild
    DTXcode
    DTSDKBuild
    DTSDKName
    DTPlatformBuild
    DTPlatformName
    DTPlatformVersion
  )
  for key in "${KEYS_TO_REMOVE[@]}"; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$INFO_PLIST" 2>/dev/null || true
  done
fi

echo "==> Normalization complete: $APP_PATH"

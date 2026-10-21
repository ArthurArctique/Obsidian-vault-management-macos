#!/usr/bin/env bash
# make_icon.sh — Génère Resources/AppIcon.icns (squircle violet + livres blancs).
# À relancer uniquement si l'on veut régénérer l'icône.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "🎨 Rendu du PNG 1024×1024…"
swift "${ROOT}/scripts/make_icon.swift" "${TMP}/icon_1024.png"

echo "🧩 Assemblage de l'iconset…"
ICONSET="${TMP}/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="${TMP}/icon_1024.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SRC" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    if [[ $double -eq 1024 ]]; then
        cp "$SRC" "${ICONSET}/icon_${size}x${size}@2x.png"
    else
        sips -z "$double" "$double" "$SRC" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
    fi
done

echo "📦 Création de Resources/AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "${ROOT}/Resources/AppIcon.icns"

echo "✅ Icône générée : Resources/AppIcon.icns"

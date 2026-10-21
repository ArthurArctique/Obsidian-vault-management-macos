#!/usr/bin/env bash
# build.sh — Compile ObsiVaults et l'empaquète dans build/ObsiVaults.app
# Binaire universel (arm64 + x86_64) : marche sur les Mac Intel et Apple Silicon.
#
#   ./build.sh            compile dans build/
#   ./build.sh --install  compile puis copie l'app dans /Applications
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ObsiVaults"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
MIN_MACOS="13.0"

INSTALL=0
case "${1:-}" in
    "") ;;
    --install) INSTALL=1 ;;
    *) echo "Usage : ./build.sh [--install]" >&2; exit 2 ;;
esac

SWIFT_SOURCES=(Sources/*.swift)

echo "🔨 Compilation de ${APP_NAME} (binaire universel arm64 + x86_64)…"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

for arch in arm64 x86_64; do
    swiftc "${SWIFT_SOURCES[@]}" \
        -swift-version 5 \
        -O \
        -target "${arch}-apple-macos${MIN_MACOS}" \
        -o "${BUILD_DIR}/${APP_NAME}_${arch}"
done

lipo -create "${BUILD_DIR}/${APP_NAME}_arm64" "${BUILD_DIR}/${APP_NAME}_x86_64" \
    -output "${MACOS_DIR}/${APP_NAME}"
rm -f "${BUILD_DIR}/${APP_NAME}_arm64" "${BUILD_DIR}/${APP_NAME}_x86_64"

cp Resources/Info.plist "${CONTENTS}/Info.plist"

# Icône de l'app, régénérable avec scripts/make_icon.sh
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

# Signature ad-hoc (sans certificat Apple Developer) : macOS refuse de lancer un binaire arm64
# non signé, et l'ouverture à la connexion a besoin d'une app signée.
#
# Le Bureau est synchronisé avec iCloud Drive : le système y remet des attributs étendus
# (com.apple.FinderInfo…) que codesign refuse (« resource fork … detritus not allowed »).
# On les efface juste avant chaque tentative, et on réessaie si la synchronisation a été plus rapide.
sign_and_verify() {
    local bundle="$1"
    for attempt in 1 2 3 4 5; do
        xattr -cr "${bundle}" 2>/dev/null || true
        if codesign --force --deep -s - --identifier "fr.arthur.obsivaults" "${bundle}" 2>/dev/null \
            && xattr -cr "${bundle}" 2>/dev/null \
            && codesign --verify --deep --strict "${bundle}" 2>/dev/null; then
            return 0
        fi
        echo "↻ Attribut étendu réapparu pendant la signature : nouvelle tentative $((attempt + 1))/5…"
        sleep 1
    done
    echo "❌ Impossible de signer ${bundle} après 5 tentatives." >&2
    return 1
}

sign_and_verify "${APP_BUNDLE}"
echo "✅ Application créée : ${APP_BUNDLE}"

if [[ ${INSTALL} -eq 1 ]]; then
    TARGET="/Applications/${APP_NAME}.app"
    # Une copie déjà lancée doit être quittée avant d'être remplacée.
    if pgrep -x "${APP_NAME}" >/dev/null; then
        echo "⏹  Fermeture de ${APP_NAME}…"
        pkill -x "${APP_NAME}" || true
        sleep 1
    fi
    rm -rf "${TARGET}"
    ditto "${APP_BUNDLE}" "${TARGET}"
    sign_and_verify "${TARGET}"
    echo "📦 Installée : ${TARGET}"
    echo ""
    echo "▶  Pour lancer : open \"${TARGET}\""
else
    echo ""
    echo "▶  Pour lancer :     open ${APP_BUNDLE}"
    echo "▶  Pour installer :  ./build.sh --install"
fi

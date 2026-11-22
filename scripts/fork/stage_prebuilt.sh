#!/bin/bash
# Fork de Alvarocrack: prepara lo que la app necesita para compilarse sin rehacer QEMU, ANGLE, MoltenVK ni la capa de PS4.
#
# Compilar todo desde cero (scripts/ci_build.sh) lleva horas: ANGLE solo ya es un mundo. Pero esas piezas no cambian con los
# cambios del fork, que son de la app y de la capa de traducción. Así que se sacan del IPA publicado por Leviidev (la última
# release) y se dejan donde project.yml y package_ipa.sh las esperan. Luego basta con xcodebuild.
#
# Uso: scripts/fork/stage_prebuilt.sh [ruta/a/un/Husk.ipa]
# Sin argumento descarga el IPA de la última release de Leviidev/Husk (necesita gh con GH_TOKEN), y si no puede, el de la
# release "base-ipa" de este fork.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPS="$ROOT/build/fork-deps"
rm -rf "$DEPS"
mkdir -p "$DEPS/dl"

IPA="${1:-}"
if [ -z "$IPA" ]; then
    if gh release download --repo Leviidev/Husk --pattern '*.ipa' --dir "$DEPS/dl" --clobber 2>/dev/null; then
        TAG="$(gh release view --repo Leviidev/Husk --json tagName --jq .tagName 2>/dev/null || echo latest)"
        echo "==> base: Leviidev/Husk $TAG"
    elif [ -n "${GITHUB_REPOSITORY:-}" ] && gh release download base-ipa --repo "$GITHUB_REPOSITORY" --pattern '*.ipa' --dir "$DEPS/dl" --clobber; then
        echo "==> base: release base-ipa de $GITHUB_REPOSITORY"
    else
        echo "no se pudo descargar un IPA base" >&2
        exit 1
    fi
    # el .ipa más grande (no el .tipa de TrollStore)
    IPA="$(ls -S "$DEPS"/dl/*.ipa | head -1)"
fi
echo "==> IPA base: $IPA ($(du -h "$IPA" | cut -f1))"

unzip -q "$IPA" -d "$DEPS/x"
APP="$(ls -d "$DEPS"/x/Payload/*.app | head -1)"
need() { [ -e "$APP/$1" ] || { echo "el IPA base no tiene $1" >&2; exit 1; }; }
for f in Frameworks/libqemu-aarch64-softmmu.dylib Frameworks/libANGLE-shared.dylib Frameworks/libhuskps4.dylib \
         Frameworks/MoltenVK.framework vmlinuz-virt initramfs-virt edk2-aarch64-code.fd java-runtime; do need "$f"; done

LIB="$ROOT/build/ios-arm64/lib"
SYSLIB="$ROOT/build/ios-arm64/sysroot/lib"
mkdir -p "$LIB" "$SYSLIB"
cp "$APP/Frameworks/libqemu-aarch64-softmmu.dylib" "$LIB/"
cp "$APP/Frameworks/libhuskps4.dylib" "$LIB/"
cp "$APP/Frameworks/libANGLE-shared.dylib" "$SYSLIB/"

# MoltenVK: el IPA lleva el .framework; el proyecto espera un .xcframework.
rm -rf "$LIB/MoltenVK.xcframework"
if ! xcodebuild -create-xcframework -framework "$APP/Frameworks/MoltenVK.framework" -output "$LIB/MoltenVK.xcframework" >/dev/null 2>&1; then
    echo "==> xcodebuild -create-xcframework falló; xcframework hecho a mano"
    mkdir -p "$LIB/MoltenVK.xcframework/ios-arm64"
    cp -R "$APP/Frameworks/MoltenVK.framework" "$LIB/MoltenVK.xcframework/ios-arm64/"
    cat > "$LIB/MoltenVK.xcframework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key>
			<string>MoltenVK.framework/MoltenVK</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>MoltenVK.framework</string>
			<key>SupportedArchitectures</key>
			<array><string>arm64</string></array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST
fi

# El invitado de Android (QEMU) y su firmware, como los deja fetch_phase0_guest.sh / fetch_sources.sh.
mkdir -p "$ROOT/guests/phase0"
cp "$APP/vmlinuz-virt" "$APP/initramfs-virt" "$ROOT/guests/phase0/"
BIOS="$ROOT/third_party/build/qemu-10.0.12-utm/pc-bios"
mkdir -p "$BIOS"
[ -d "$APP/pc-bios" ] && cp "$APP"/pc-bios/* "$BIOS/" 2>/dev/null || true
bzip2 -c "$APP/edk2-aarch64-code.fd" > "$BIOS/edk2-aarch64-code.fd.bz2"

# /system de Android (fuentes, certificados) y el runtime de Java.
mkdir -p "$ROOT/build/android-system" "$ROOT/build/java-runtime"
[ -d "$APP/android-system" ] && rsync -a --delete "$APP/android-system/" "$ROOT/build/android-system/"
rsync -a --delete "$APP/java-runtime/" "$ROOT/build/java-runtime/"

echo "==> listo: dylibs, MoltenVK, invitado, firmware, android-system y java-runtime del IPA base"

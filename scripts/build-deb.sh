#!/usr/bin/env bash
# Build a Debian package for Speech to Text.
# Copyright (C) 2026 Christos A. Daggas
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."

# Rust toolchain (rustup) may live in the user's cargo bin.
export PATH="$HOME/.cargo/bin:$PATH"

for tool in python3 dpkg-deb msgfmt desktop-file-validate appstreamcli; do
    command -v "$tool" >/dev/null || { echo "error: $tool is required; see CONTRIBUTING.md" >&2; exit 1; }
done

bash scripts/version.sh --check
VERSION=$(bash scripts/version.sh)

desktop-file-validate data/com.chrisdaggas.speech-to-text.desktop
appstreamcli validate --no-net data/com.chrisdaggas.speech-to-text.metainfo.xml

BIN="$PWD/target/release/speech-to-text"
[ -x "$BIN" ] || { echo "error: release binary not found at $BIN; build it first" >&2; exit 1; }
[ "$("$BIN" --version)" = "Speech to Text $VERSION" ] || {
    echo "error: the binary version does not match Cargo.toml" >&2; exit 1
}
[ "$("$BIN" --engine-version)" = "whisper.cpp 1.9.5" ] || {
    echo "error: unexpected native Whisper engine version" >&2; exit 1
}
grep -qa ggml_vulkan "$BIN" || { echo "error: Vulkan backend is missing" >&2; exit 1; }
if grep -qaF "$HOME/" "$BIN"; then
    echo "error: the release binary still contains a workstation home path" >&2
    exit 1
fi

STAGE=$(mktemp -d /tmp/opencode/deb-stage.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/speech-to-text_${VERSION}-1_amd64"
mkdir -p "$PKG/DEBIAN" \
    "$PKG/usr/bin" \
    "$PKG/usr/share/applications" \
    "$PKG/usr/share/icons/hicolor/scalable/apps" \
    "$PKG/usr/share/icons/hicolor/symbolic/apps" \
    "$PKG/usr/share/metainfo" \
    "$PKG/usr/share/speech-to-text" \
    "$PKG/usr/share/doc/speech-to-text"

install -m755 "$BIN" "$PKG/usr/bin/speech-to-text"
install -m644 data/com.chrisdaggas.speech-to-text.desktop "$PKG/usr/share/applications/"
install -m644 data/com.chrisdaggas.speech-to-text.metainfo.xml "$PKG/usr/share/metainfo/"
install -m644 data/icons/hicolor/scalable/apps/com.chrisdaggas.speech-to-text.svg "$PKG/usr/share/icons/hicolor/scalable/apps/"
install -m644 data/icons/hicolor/scalable/apps/com.chrisdaggas.speech-to-text-ai.svg "$PKG/usr/share/icons/hicolor/scalable/apps/"
install -m644 data/icons/hicolor/symbolic/apps/com.chrisdaggas.speech-to-text-symbolic.svg "$PKG/usr/share/icons/hicolor/symbolic/apps/"
# Some StatusNotifier hosts only probe scalable/apps, so mirror the symbolic icon there too.
install -m644 data/icons/hicolor/symbolic/apps/com.chrisdaggas.speech-to-text-symbolic.svg "$PKG/usr/share/icons/hicolor/scalable/apps/com.chrisdaggas.speech-to-text-symbolic.svg"
install -m644 data/vad/ggml-silero-v5.1.2.bin "$PKG/usr/share/speech-to-text/"
install -m644 LICENSE "$PKG/usr/share/doc/speech-to-text/copyright"
install -m644 native/LICENSE-sherpa-onnx "$PKG/usr/share/doc/speech-to-text/LICENSE-sherpa-onnx"
install -m644 native/NOTICE "$PKG/usr/share/doc/speech-to-text/NOTICE"
install -m644 vendor/whisper-rs-sys/whisper.cpp/LICENSE "$PKG/usr/share/doc/speech-to-text/LICENSE-whisper.cpp"
install -m644 vendor/whisper-rs-sys/LICENSE "$PKG/usr/share/doc/speech-to-text/LICENSE-whisper-rs-sys"

mapfile -t langs < <(grep -v '^\s*#' po/LINGUAS | tr -s ' \n' '\n' | grep -v '^$')
for lang in "${langs[@]}"; do
    mkdir -p "$PKG/usr/share/locale/$lang/LC_MESSAGES"
    msgfmt -c "po/${lang}.po" -o "$PKG/usr/share/locale/$lang/LC_MESSAGES/speech-to-text.mo"
done

INSTALLED_SIZE=$(du -sk "$PKG" | cut -f1)

cat > "$PKG/DEBIAN/control" <<EOF
Package: speech-to-text
Version: ${VERSION}-1
Section: sound
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-4-1 (>= 4.14), libadwaita-1-0 (>= 1.5), libasound2, libvulkan1, libgdk-pixbuf-2.0-0, libc6, libgcc-s1
Recommends: xdg-desktop-portal-gnome, gnome-keyring
Maintainer: Christos A. Daggas <info@chrisdaggas.com>
Homepage: https://chrisdaggas.com
Description: Native Linux desktop application for offline speech-to-text transcription
 Speech to Text turns your voice and audio recordings into text on your
 computer. Whisper, Parakeet and Qwen3-ASR process audio locally after
 downloading a model.
 .
 Optional AI tools send transcript text to a service you choose. The startup
 update check contacts GitHub and can be disabled in Settings.
EOF

OUT="$PWD/dist/deb"
mkdir -p "$OUT"
DEB="$OUT/speech-to-text_${VERSION}-1_amd64.deb"
rm -f "$DEB" "$DEB.sha256"
dpkg-deb --build --root-owner-group -Zxz "$PKG" "$DEB"
(cd "$OUT" && sha256sum "$(basename "$DEB")" > "$(basename "$DEB").sha256")
echo "built: dist/deb/$(basename "$DEB")"
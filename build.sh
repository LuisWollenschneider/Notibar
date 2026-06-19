#!/bin/bash
# Build Notibar.app from Swift sources (no Xcode project required).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Notibar"
BUNDLE_ID="com.notibar.app"
APP_DIR="${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "==> Cleaning previous build"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

echo "==> Compiling Swift sources"
swiftc \
    -O \
    -parse-as-library \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework ServiceManagement \
    -framework ApplicationServices \
    -framework CoreImage \
    Sources/*.swift

echo "==> Writing Info.plist"
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>        <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>         <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>         <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>            <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleIconFile</key>           <string>Icon</string>
    <key>CFBundleIconName</key>           <string>Icon</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHumanReadableCopyright</key>   <string>Notibar</string>
</dict>
</plist>
PLIST

echo "==> Writing PkgInfo"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> Compiling app icon"
# Icon.icon is an Icon Composer source bundle; actool compiles it into
# Assets.car + Icon.icns (referenced by CFBundleIconFile/CFBundleIconName above).
actool Icon.icon \
    --compile "${RES_DIR}" \
    --app-icon Icon \
    --output-partial-info-plist "$(mktemp -t notibar-icon)" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --errors --warnings >/dev/null

# Sign with a stable self-signed identity so the Accessibility grant survives
# rebuilds. Ad-hoc signatures get a fresh cdhash each build, which makes macOS
# silently revoke the Accessibility permission (badges then stop reading).
SIGN_ID="Notibar Self-Signed"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

ensure_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_ID}"; then
        return 0
    fi
    echo "==> Creating self-signed codesigning identity '${SIGN_ID}'"
    echo "    (macOS may prompt for your login password to trust it — one time only)"
    local tmp; tmp="$(mktemp -d)"
    # Self-signed cert with the codeSigning EKU.
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "${tmp}/key.pem" -out "${tmp}/cert.pem" \
        -subj "/CN=${SIGN_ID}" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
    # Legacy PKCS#12 encoding (SHA1/3DES) — Apple's importer rejects OpenSSL 3 defaults.
    openssl pkcs12 -export -legacy -inkey "${tmp}/key.pem" -in "${tmp}/cert.pem" \
        -out "${tmp}/id.p12" -passout pass:notibar -name "${SIGN_ID}" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 >/dev/null 2>&1 \
        || { rm -rf "${tmp}"; return 1; }
    security import "${tmp}/id.p12" -k "${LOGIN_KEYCHAIN}" -P notibar -A \
        -T /usr/bin/codesign >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
    # Trust the cert for code signing so codesign will use it and TCC honors the
    # stable Designated Requirement (this is what makes the grant survive rebuilds).
    security add-trusted-cert -r trustRoot -p codeSign -k "${LOGIN_KEYCHAIN}" \
        "${tmp}/cert.pem" >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
    rm -rf "${tmp}"
}

echo "==> Code signing"
if ensure_identity && security find-identity -v -p codesigning | grep -q "${SIGN_ID}"; then
    codesign --force --deep --sign "${SIGN_ID}" --identifier "${BUNDLE_ID}" "${APP_DIR}"
    echo "    signed with '${SIGN_ID}' (grant persists across rebuilds)"
else
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
    echo "    ad-hoc signed — Accessibility must be re-granted after each rebuild"
fi

echo "==> Done: ${APP_DIR}"
echo "    Run with: open \"${APP_DIR}\""
echo "    First launch: grant Accessibility permission in System Settings > Privacy & Security."

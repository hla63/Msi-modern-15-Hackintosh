#!/bin/bash
# Compile, sign and register the MSIECToolbox LaunchAgent.
#
# Run it as the user who will use the agent, WITHOUT sudo:
#   ./build_and_install.sh
# SMAppService registers the agent in the session of whoever runs the
# installer, so it must not run as root. The script asks for sudo itself,
# only for the copies into /Applications and /Library.
#
# Code signing — SIGN_IDENTITY selects the codesign identity (default "-",
# ad-hoc). The Accessibility permission (CGEventTap) is tied to the code
# signature: with ad-hoc signing it has to be granted again after every
# rebuild. A stable identity keeps it, e.g. a self-signed "Code Signing"
# certificate created in Keychain Access (Certificate Assistant):
#   SIGN_IDENTITY="MSIECToolbox Local" ./build_and_install.sh
#
# Agent logs go to the unified log:
#   log stream --predicate 'process == "MSIECToolboxAgent"'
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "❌ Ne pas lancer ce script avec sudo." >&2
    echo "   Lancez-le avec votre compte : ./build_and_install.sh" >&2
    echo "   (sudo est demandé automatiquement pour les étapes qui en ont besoin)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="/Applications/MSIECToolbox.app"
LEGACY_APP_PATH="/Applications/MSIECTOOLBOX.app"
SUPPORT_DIR="/Library/Application Support/MSIECToolbox"
AGENT_DST="$SUPPORT_DIR/MSIECToolboxAgent"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Private build directory: fixed names in /tmp could be swapped by another
# process between compilation and the sudo copy.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/msiectoolbox.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "=== MSIECToolbox — Installation ==="
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "ℹ️  Signature ad-hoc : l'autorisation Accessibilité devra être"
    echo "   ré-accordée après chaque recompilation (voir SIGN_IDENTITY en tête du script)."
else
    # Without -v: a self-signed certificate is listed even when it is not
    # trusted, and codesign can still sign with it.
    if ! security find-identity -p codesigning | grep -qF "\"$SIGN_IDENTITY\""; then
        echo "❌ Identité de signature \"$SIGN_IDENTITY\" introuvable dans le trousseau." >&2
        echo "   Identités disponibles :" >&2
        security find-identity -p codesigning >&2 || true
        echo "   Pour en créer une : Trousseau d'accès › Assistant de certification ›" >&2
        echo "   Créer un certificat… › Nom : \"$SIGN_IDENTITY\", Type d'identité :" >&2
        echo "   Racine auto-signée, Type de certificat : Signature de code." >&2
        echo "   Ou relancez sans SIGN_IDENTITY pour une signature ad-hoc." >&2
        exit 1
    fi
fi
sudo -v

# 1. Compiler, signer et installer l'agent
echo "→ Compilation de l'agent..."
swiftc "$SCRIPT_DIR"/Sources/*.swift \
    -module-name MSIECToolboxAgent \
    -o "$BUILD_DIR/MSIECToolboxAgent" \
    -framework Foundation \
    -framework CoreAudio \
    -framework IOKit \
    -framework CoreGraphics \
    -framework AppKit \
    -O

# Hardened runtime: DYLD_INSERT_LIBRARIES and unsigned libraries are refused,
# so no other process can run code with the agent's Accessibility permission.
# Signed as the user (codesign under sudo cannot reach the login keychain);
# the signature is embedded in the binary and survives the copy.
# agent.entitlements grants Core Audio input access, which the hardened
# runtime otherwise denies (mic mute key and mic LED sync).
codesign --force --options runtime \
    --identifier com.msi.MSIECToolboxAgent \
    --entitlements "$SCRIPT_DIR/agent.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$BUILD_DIR/MSIECToolboxAgent"

sudo mkdir -p "$SUPPORT_DIR"
sudo install -o root -g wheel -m 755 "$BUILD_DIR/MSIECToolboxAgent" "$AGENT_DST"
codesign --verify --strict "$AGENT_DST"
echo "   ✅ Agent signé et installé dans $AGENT_DST"

# 2. Désenregistrer l'ancien LaunchAgent launchctl si présent
OLD_PLIST="$HOME/Library/LaunchAgents/com.msi.MSIECToolboxAgent.plist"
if [ -f "$OLD_PLIST" ]; then
    echo "→ Suppression ancien LaunchAgent launchctl..."
    launchctl unload "$OLD_PLIST" 2>/dev/null || true
    rm -f "$OLD_PLIST"
    echo "   ✅ Ancien plist supprimé"
fi

# 3. Compiler le binaire installeur
echo "→ Compilation de l'installeur..."
swiftc "$SCRIPT_DIR/MSIECToolboxInstaller.swift" \
    -o "$BUILD_DIR/MSIECToolboxInstaller" \
    -framework Foundation \
    -framework ServiceManagement \
    -O
echo "   ✅ Installeur compilé"

# 4. Construire et signer le bundle app dans le dossier privé
echo "→ Création de MSIECToolbox.app..."
BUNDLE="$BUILD_DIR/MSIECToolbox.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Library/LaunchAgents"
cp "$BUILD_DIR/MSIECToolboxInstaller" "$BUNDLE/Contents/MacOS/MSIECToolboxInstaller"
cp "$SCRIPT_DIR/Info.plist"           "$BUNDLE/Contents/Info.plist"

# Plist de l'agent (dans le bundle). No StandardOutPath/StandardErrorPath:
# fixed files in /tmp are readable and pre-creatable by other users, and
# NSLog already writes to the unified log.
cat > "$BUNDLE/Contents/Library/LaunchAgents/com.msi.MSIECToolboxAgent.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.msi.MSIECToolboxAgent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/Application Support/MSIECToolbox/MSIECToolboxAgent</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>
</dict>
</plist>
PLISTEOF

echo "→ Signature du bundle..."
codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
echo "   ✅ Bundle signé"

# 5. Installer le bundle
if [ -d "$LEGACY_APP_PATH" ] && ! [ "$LEGACY_APP_PATH" -ef "$APP_PATH" ]; then
    echo "→ Suppression de l'ancien bundle $LEGACY_APP_PATH..."
    sudo rm -rf "$LEGACY_APP_PATH"
fi
sudo rm -rf "$APP_PATH"
sudo ditto "$BUNDLE" "$APP_PATH"
sudo chown -R root:wheel "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "   ✅ Bundle installé dans $APP_PATH"

# 6. Enregistrer via SMAppService (dans la session de l'utilisateur courant)
#    On ne fait unregister+register que si le binaire agent a changé
#    (le register() déclenche une notification système à chaque appel
#    si le bundle a été recréé — on évite ça en vérifiant le checksum).
AGENT_CHECKSUM_FILE="$SUPPORT_DIR/.agent_checksum"
NEW_CHECKSUM=$(shasum -a 256 "$AGENT_DST" | awk '{print $1}')
OLD_CHECKSUM=$(cat "$AGENT_CHECKSUM_FILE" 2>/dev/null || echo "")

STATUS=$("$APP_PATH/Contents/MacOS/MSIECToolboxInstaller" status 2>/dev/null || echo "")

if [ "$NEW_CHECKSUM" != "$OLD_CHECKSUM" ] || [[ "$STATUS" != *"✅"* ]]; then
    echo "→ Désenregistrement préalable (unregister)..."
    "$APP_PATH/Contents/MacOS/MSIECToolboxInstaller" unregister 2>/dev/null || true

    echo "→ Enregistrement (register)..."
    "$APP_PATH/Contents/MacOS/MSIECToolboxInstaller" register

    # Sauvegarder le checksum pour éviter les re-registrations inutiles
    echo "$NEW_CHECKSUM" | sudo tee "$AGENT_CHECKSUM_FILE" > /dev/null
else
    echo "→ Agent inchangé et déjà enregistré — pas de re-registration"
    echo "   (évite la notification 'Éléments en arrière-plan' répétée)"
fi

echo ""
echo "=== Installation terminée ==="
echo "Si le statut indique 'En attente approbation' :"
echo "→ Réglages Système > Général > Ouverture > activer MSIECToolbox"
echo "Touches Fn (CGEventTap) :"
echo "→ Réglages Système > Confidentialité et sécurité > Accessibilité > MSIECToolboxAgent"

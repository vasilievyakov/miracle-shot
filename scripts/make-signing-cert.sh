#!/bin/bash
# Creates a self-signed code-signing identity "Miracle Shot Dev" in the login keychain, once.
# With it, the app's designated requirement is identifier + certificate instead of the per-build cdhash,
# so the Screen Recording permission survives rebuilds. macOS will ask for your login password.
set -euo pipefail
NAME="Miracle Shot Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/ext.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:miracle -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:miracle

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P miracle -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust the certificate for code signing (user trust settings; macOS asks for your password).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
# Let codesign use the private key without a prompt on every build (asks for the login password once).
read -r -s -p "Login keychain password (to allow codesign to use the key silently): " PW; echo
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KEYCHAIN" >/dev/null

security find-identity -v -p codesigning | grep "$NAME" && echo "Done. scripts/build-app.sh will now sign with '$NAME'."

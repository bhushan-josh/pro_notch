#!/bin/bash
# Creates a self-signed "Dynamic Notch Local" code-signing identity in the login keychain.
# Signing every build with the same identity keeps macOS privacy grants across rebuilds.
set -euo pipefail

NAME="Dynamic Notch Local"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" >/dev/null 2>&1
PASS="dynamic-notch"
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
       -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1

security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in the login keychain."

#!/bin/bash
# Creates a self-signed "Dynamic Notch Local" code-signing identity in a project-local keychain.
# A dedicated keychain with a known password lets codesign use the key without prompting, and keeps
# the login keychain untouched. Signing every build with the same identity keeps macOS privacy grants.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Dynamic Notch Local"
KEYCHAIN="$ROOT/.signing/dynamic-notch.keychain-db"
# Not a secret: it only guards a throwaway self-signed key used for local builds.
KEYCHAIN_PASSWORD="dynamic-notch-local"

mkdir -p "$ROOT/.signing"
if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in $KEYCHAIN."
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
P12_PASS="dynamic-notch"
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
       -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1

rm -f "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
echo "Created \"$NAME\" in $KEYCHAIN."

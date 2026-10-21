#!/bin/sh
# Builds Proton Mail Bridge (no GUI) with its API pointed at Proton's onion service.
# Usage: ./build.sh [release-tag]   (defaults to the latest v3.* tag)
set -e
cd "$(dirname "$0")"
KIT_DIR=$(pwd)
TAG=${1:-$(git ls-remote --tags --refs https://github.com/ProtonMail/proton-bridge.git 'v3.*' | awk -F/ '{print $3}' | sort -V | tail -1)}
SRC=${BRIDGE_SRC:-"$KIT_DIR/proton-bridge"}

echo "Building Proton Mail Bridge $TAG (onion API) in $SRC"
rm -rf "$SRC"
git clone --depth 1 --branch "$TAG" https://github.com/ProtonMail/proton-bridge.git "$SRC"
cd "$SRC"
git apply "$KIT_DIR/patches/onion-api-host.patch"
grep -q 'onion/api' internal/constants/host_default.go

# Static libfido2 for both architectures, the way upstream's Makefile expects it.
make install-libfido2
make build-nogui

echo "Built: $SRC/bridge"
echo "Run it through Tor: HTTPS_PROXY=socks5://127.0.0.1:9050 HTTP_PROXY=socks5://127.0.0.1:9050 NO_PROXY=localhost,127.0.0.1 $SRC/bridge --cli"

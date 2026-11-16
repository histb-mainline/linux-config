#!/bin/sh
# Fetch the latest Debian kernel configuration for one architecture.
#
# Debian no longer ships /boot/config-* with the kernel images. The generated
# configuration is published in the linux-config-<major> source package as
# usr/src/linux-config-<major>/config.<arch>_none_<flavor>.xz. This script
# downloads the newest such binary package from a Debian mirror and writes the
# uncompressed config to <outdir>/debian32.config (armhf) or
# <outdir>/debian64.config (arm64).
#
# The output directory is a working directory: it holds raw material for the
# layer merge and is not part of this repository.
#
# usage: fetch-debian-config.sh <armhf|arm64> [outdir]
set -eu
ARCH=${1:?usage: fetch-debian-config.sh <armhf|arm64> [outdir]}
OUTDIR=${2:-.}
MIRROR=${MIRROR:-https://deb.debian.org/debian}

case "$ARCH" in
	armhf) OUT=debian32.config; FLAVOR=armmp ;;
	arm64) OUT=debian64.config; FLAVOR=arm64 ;;
	*) echo "unsupported arch: $ARCH (use armhf or arm64)" >&2; exit 2 ;;
esac

POOL="$MIRROR/pool/main/l/linux/"
LIST=$(curl -fsSL "$POOL")
DEB=$(printf '%s\n' "$LIST" |
	grep -oE "linux-config-[0-9.]+_[^\"<>]*_${ARCH}\.deb" |
	sort -uV | tail -1)
[ -n "$DEB" ] || { echo "no linux-config package found for $ARCH" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/pkg.deb" "$POOL$DEB"
dpkg-deb -x "$TMP/pkg.deb" "$TMP/root"
XZ=$(find "$TMP/root" -name "config.${ARCH}_none_${FLAVOR}.xz")
[ -n "$XZ" ] || { echo "config.${ARCH}_none_${FLAVOR}.xz not found in $DEB" >&2; exit 1; }

mkdir -p "$OUTDIR"
xz -dc "$XZ" > "$OUTDIR/$OUT"
echo "$OUTDIR/$OUT  from $DEB  $(stat -c %s "$OUTDIR/$OUT") bytes"

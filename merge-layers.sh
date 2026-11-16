#!/bin/sh
# Layer merge around the kconfig tools shipped in the kernel tree:
# copy a working config, merge the given layer fragments, let olddefconfig
# resolve dependencies. One merge plus one olddefconfig produces the product
# (olddefconfig reads all recorded values first and resolves afterwards;
# file order only matters for duplicate assignments of the same symbol, where
# the last one wins).
#
# usage: KDIR=<kernel tree> KCONFIG_CONFIG=<working config> merge-layers.sh \
#            <arm|arm64> <layer files...>
set -eu
KDIR=${KDIR:?set KDIR to the kernel tree}
ARCH=$1; shift
OUT=${KCONFIG_CONFIG:?set KCONFIG_CONFIG to the working config}

case $ARCH in
	arm)    X="ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-" ;;
	arm64)  X="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-" ;;
	*) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac

[ -f "$OUT" ] || { echo "working config $OUT missing -- cp the fetched" \
	"baseline (base/debian32.config / base/debian64.config) to $OUT first," \
	"or run alldefconfig for the debug line" >&2; exit 2; }
KCONFIG_CONFIG=$OUT "$KDIR/scripts/kconfig/merge_config.sh" -m $OUT "$@"
# shellcheck disable=SC2086
make -C "$KDIR" $X KCONFIG_CONFIG="$OUT" olddefconfig < /dev/null

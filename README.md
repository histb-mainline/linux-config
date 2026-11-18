# HiSTB board kernel configuration fragments

The kernel is built per architecture. Boards differ only by their device tree
and the carrier packaging. The configuration is layered, never maintained as a
hand-edited `.config`, and never trimmed per board.

This repository contains the generation method only: the fragments below plus
a fetch script for the distribution baseline. Raw baselines, generated
products and verification output are working files and are not committed.

## Layers

| Layer | File | Content |
|---|---|---|
| 0 base | `debian32.config`, `debian64.config` (repo top, gitignored, fetched by `fetch-debian-config.sh`) | Debian kernel config for armmp / arm64, fetched by `fetch-debian-config.sh` (not committed) |
| 1 arch | `01-arch-arm.txt`, `01-arch-arm64.txt` | **boot-critical options only**: the architecture gates, the CRG clock drivers, the per-CPU tick driver, the appended-DTB boot-protocol trio, VFP, the LPAE guard |
| 2 selection | `02-select-y.txt` / `02-select-m.txt` | every board driver demanded by the enabled device-tree nodes -- including SoC-specific IP -- in **two mutually exclusive flavors**: `-y` everything built in (release standard; boots without an initramfs), `-m` modularized (serial console and root storage stay built in; bool switches are unaffected) |
| 3 final | `03-convenience.txt` | architecture-independent de-selections (compiler debug info, kernel module signing) and on-board conveniences (filesystems, NFS, USB storage, input/debug channels, leaf crypto) |

The debug line is an `alldefconfig` base -- fully decoupled from the
distribution baseline -- plus layers 01 and 02-select-y plus the debug layers:
`03-debug-common.txt` carries the architecture-common capabilities (core
capability pins, the initramfs delivery core, the debug posture, the
deselection of the media default subtrees and the perf-events core);
`04-debug-<arch>.txt` carries the arch-specific remainder (platform/boot
gates, per-arch optimization traps, suspend diagnostics, tsensor, the per-arch
PMU symbol). Both together carry every dtb-required driver (same judgment as
the release line). `03-convenience.txt` is not applied there.

## Products

Two published products per architecture, plus the internal debug line:

| Product | Recipe | initramfs | Posture |
|---|---|---|---|
| Debian-style | arch + **select-m** | **required** -- the initramfs delivers the module set and mounts root | distribution baseline untouched |
| direct-boot | arch + **select-y** + **convenience** | not required -- every driver built in, mounts root from eMMC/NAND | de-selections from the convenience layer apply (compiler debug info, module signing) |

Both arm32 products share one zImage; boards differ only by the DTB and the
carrier packaging. The debug line (`03-debug-common.txt` + `04-debug-<arch>`
on an `alldefconfig` base) is a working tool, not a published product.

The initramfs prerequisites for the Debian-style product (`BLK_DEV_INITRD`,
`RD_GZIP`, `RD_XZ`, `DEVTMPFS`) are carried by the distribution baseline; the
serial console is the only driver select-m keeps built in.

## Recipe

```sh
./fetch-debian-config.sh armhf      # writes debian32.config at the repo top

OUT=/tmp/out.config
cp debian32.config $OUT

# release32 = 01-arch-arm -> 02-select-y -> 03-convenience
KCONFIG_CONFIG=$OUT ./merge-layers.sh arm 01-arch-arm.txt 02-select-y.txt \
    03-convenience.txt          # see merge-layers.sh below
```

For the debug line the base is `alldefconfig` instead of the distribution
config, and layer 03-convenience is not applied -- the debug layers
`03-debug-common.txt` + `04-debug-<arch>.txt` are applied instead:

```sh
KDIR=/path/to/linux
KCONFIG_CONFIG=$OUT make -C $KDIR ARCH=arm \
    CROSS_COMPILE=arm-linux-gnueabihf- alldefconfig < /dev/null
KCONFIG_CONFIG=$OUT KDIR=$KDIR ./merge-layers.sh arm \
    01-arch-arm.txt 02-select-y.txt 03-debug-common.txt 04-debug-arm.txt
```

Generate the arm64 products by swapping `debian64.config` (repo top) /
`01-arch-arm64.txt` and `ARCH=arm64`:
release64 = 01-arch-arm64 + 02-select-y + 03-convenience, debug64 =
01-arch-arm64 + 02-select-y + 03-debug-common + 04-debug-arm64.

The generated products are working files and are not committed; regenerate
them per target.

### Why one merge suffices

Kconfig's `olddefconfig` reads all recorded values first and resolves
dependencies afterwards; file order only matters for duplicate assignments of
the same symbol (the last one wins). One merge plus one olddefconfig produces
the product. Every fragment line must be verified to have landed in the
result; lines with `=n` land as `# CONFIG_X is not set`.

### Known cross-architecture absences

`PHY_HI3716CV200_SATA` depends on `ARCH_HI3716CV200` (arm32 only) and
`DRM_HISTB_HDMI` depends on `ARM64` (arm64 only): in the shared selection
layer these lines legitimately never land on the other architecture and are
reported as absent.

## Writing discipline

- Only write lines `olddefconfig` cannot infer. Symbols with `default` are not
  written -- unless a baseline pins them to another legal value
  (`CONFIG_VIDEO_DEV`), in which case the line is mandatory and must say so.
- Check the symbol type before modularizing: bools (`AMBA_PL08X`,
  `POWER_RESET_SYSCON`, `RESET_HISI`) cannot take `m`; symbols force-set by
  the tree snap back (`PINCTRL_SINGLE` rejects a user value of m and returns
  to y). Both classes stay built in under both flavors.
- Parent symbols are written before children within a fragment (readability;
  cross-layer order is irrelevant, see above).
- Deselecting a symbol requires the evidence chain of what would set it back:
  a choice member name (`DEBUG_INFO_NONE`), a dependent select
  (`MODULE_SIG` behind the LSM lockdown), or a default conditioned on a
  filter (`MEDIA_CAMERA_SUPPORT` behind `MEDIA_SUPPORT_FILTER`).
- Symbols absent on the other architecture must not be written into shared
  fragments as `=m`/`=y` expectations; they are the documented-absent class
  above.

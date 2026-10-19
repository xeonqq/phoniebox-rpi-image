#!/usr/bin/env bash
#
# Free the disk space of stale rpi-image-gen build directories.
#
# rpi-image-gen keeps the chroot and the deploy directory of every build in
# <rpi-image-gen>/work. On a small SD card two builds are enough to fill it
# up. The next build then dies while unpacking a package:
#
#   E: Sub-process env returned an error code (1)
#   ... /tmp/apt-dpkg-install-XXXX/41-docker.io_..._arm64.deb
#
# The build directories are owned by root, so run this as root:
#
#   sudo ./clean-build-space.sh /path/to/rpi-image-gen
#
set -euo pipefail

IGROOT=${1:-}
if [ -z "$IGROOT" ]; then
    echo "usage: ${0##*/} <path-to-rpi-image-gen>" >&2
    exit 1
fi

WORK="$IGROOT/work"
if [ ! -d "$WORK" ]; then
    echo "no work directory at $WORK - nothing to do"
    exit 0
fi

echo "before:"
df -h "$WORK" | tail -1

# The image output directory is recreated by every build.
for d in "$WORK"/image-*; do
    [ -d "$d" ] || continue
    echo "removing $d"
    rm -rf -- "$d"
done

# Keep the newest deploy directory that actually holds an image - that is
# the result of the last successful build. Deploy directories of failed
# builds are empty and can go. The directories are named after the build
# date, so the name order is the age order.
newest_deploy=""
for d in $(ls -1d "$WORK"/deploy-* 2>/dev/null | sort); do
    [ -d "$d" ] || continue
    ls "$d"/*.img.zst >/dev/null 2>&1 || continue
    newest_deploy="$d"
done

for d in "$WORK"/chroot-* "$WORK"/deploy-*; do
    [ -d "$d" ] || continue
    if [ "$d" = "$newest_deploy" ]; then
        echo "keeping $d"
        continue
    fi
    echo "removing $d"
    rm -rf -- "$d"
done

echo "after:"
df -h "$WORK" | tail -1

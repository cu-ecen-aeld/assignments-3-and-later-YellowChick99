#!/bin/bash
set -e
set -u

KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
SYSROOT="$(${CROSS_COMPILE}gcc -print-sysroot)"

OUTDIR="${1:-${OUTDIR:-/tmp/aesd-autograder}}"
mkdir -p "${OUTDIR}"

cd "${OUTDIR}"
if [ ! -d linux-stable ]; then
    git clone "${KERNEL_REPO}" --depth 1 --single-branch --branch "${KERNEL_VERSION}" linux-stable
fi

cd "${OUTDIR}/linux-stable"
if [ ! -f "arch/${ARCH}/boot/Image" ]; then
    git checkout "${KERNEL_VERSION}"
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
    make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" all
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" dtbs
fi

cp -f "arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

rm -rf "${OUTDIR}/rootfs"
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin var/log

cd "${OUTDIR}"
if [ ! -d busybox ]; then
    git clone https://github.com/mirror/busybox.git busybox
    cd busybox
    git checkout "${BUSYBOX_VERSION}"
    make distclean
    make defconfig
else
    cd busybox
fi

make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" install

cd "${OUTDIR}/rootfs"
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

cp -a "${SYSROOT}/lib/ld-linux-aarch64.so.1" lib/
cp -a "${SYSROOT}/lib64/libm.so.6" lib64/
cp -a "${SYSROOT}/lib64/libresolv.so.2" lib64/
cp -a "${SYSROOT}/lib64/libc.so.6" lib64/

sudo -n mknod -m 666 dev/null c 1 3 || true
sudo -n mknod -m 600 dev/console c 5 1 || true

make -C "${FINDER_APP_DIR}" clean || true
make -C "${FINDER_APP_DIR}" CROSS_COMPILE="${CROSS_COMPILE}"

mkdir -p "${OUTDIR}/rootfs/home"
cp "${FINDER_APP_DIR}/writer" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/"
cp -aL "${FINDER_APP_DIR}/conf" "${OUTDIR}/rootfs/home/"

sed -i 's#\.\./conf/assignment\.txt#conf/assignment.txt#g' "${OUTDIR}/rootfs/home/finder-test.sh"

sudo -n chown -hR root:root "${OUTDIR}/rootfs" || true

cd "${OUTDIR}/rootfs"
find . -print0 | cpio --null -H newc -ov --owner root:root | gzip -9 > "${OUTDIR}/initramfs.cpio.gz"

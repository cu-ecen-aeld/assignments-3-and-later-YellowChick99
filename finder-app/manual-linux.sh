#!/bin/bash

set -e
set -u

outdir=/tmp/aesd-autograder
kernel_repo=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
kernel_version=v5.15.163
busybox_version=1_33_1
finder_app_dir=$(realpath $(dirname $0))
arch=arm64
cross_compile=aarch64-none-linux-gnu-
sysroot=$(${cross_compile}gcc -print-sysroot)

export arch=${arch}
export cross_compile=${cross_compile}

if [ $# -ge 1 ]; then
	outdir=$1
fi

mkdir -p ${outdir}

cd ${outdir}
if [ ! -d ${outdir}/linux-stable ]; then
	git clone ${kernel_repo} --depth 1 --single-branch --branch ${kernel_version} linux-stable
fi

if [ ! -e ${outdir}/linux-stable/arch/${arch}/boot/Image ]; then
	cd ${outdir}/linux-stable
	git checkout ${kernel_version}
	make mrproper
	make defconfig
	make -j$(nproc) all
	make modules
	make dtbs
fi

cd ${outdir}
rm -f Image
cp ${outdir}/linux-stable/arch/${arch}/boot/Image ${outdir}/

if [ -d ${outdir}/rootfs ]; then
	sudo rm -rf ${outdir}/rootfs
fi

mkdir -p ${outdir}/rootfs
cd ${outdir}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/lib usr/sbin var/log

cd ${outdir}
if [ ! -d ${outdir}/busybox ]; then
	git clone https://github.com/mirror/busybox.git busybox
	cd busybox
	git checkout ${busybox_version}
	make distclean
	make defconfig
else
	cd busybox
fi

make arch=${arch} cross_compile=${cross_compile}
make config_prefix=${outdir}/rootfs arch=${arch} cross_compile=${cross_compile} install

cd ${outdir}/rootfs
${cross_compile}readelf -a bin/busybox | grep "program interpreter"
${cross_compile}readelf -a bin/busybox | grep "Shared library"

cp -a ${sysroot}/lib/ld-linux-aarch64.so.1 ${outdir}/rootfs/lib/
cp -a ${sysroot}/lib64/libm.so.6 ${outdir}/rootfs/lib64/
cp -a ${sysroot}/lib64/libresolv.so.2 ${outdir}/rootfs/lib64/
cp -a ${sysroot}/lib64/libc.so.6 ${outdir}/rootfs/lib64/

sudo mknod -m 666 ${outdir}/rootfs/dev/null c 1 3
sudo mknod -m 600 ${outdir}/rootfs/dev/console c 5 1

cd ${finder_app_dir}
make clean
make cross_compile=${cross_compile}

mkdir -p ${outdir}/rootfs/home
cp writer ${outdir}/rootfs/home/
cp finder.sh ${outdir}/rootfs/home/
cp finder-test.sh ${outdir}/rootfs/home/
cp autorun-qemu.sh ${outdir}/rootfs/home/
cp -r conf ${outdir}/rootfs/home/

sed -i 's#\.\./conf/assignment\.txt#conf/assignment.txt#g' ${outdir}/rootfs/home/finder-test.sh

sudo chown -hR root:root ${outdir}/rootfs

cd ${outdir}/rootfs
find . | cpio -H newc -ov --owner root:root > ${outdir}/initramfs.cpio
cd ${outdir}
gzip -f initramfs.cpio

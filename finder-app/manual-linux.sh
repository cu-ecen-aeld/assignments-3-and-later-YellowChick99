#!/bin/bash
set -euo pipefail

outdir=${1:-/tmp/aeld}
outdir=$(realpath "$outdir")

mkdir -p "$outdir"
if [ ! -d "$outdir" ]; then
  echo "failed to create outdir: $outdir"
  exit 1
fi

arch=arm64
cross_prefix=aarch64-none-linux-gnu-
sysroot=$(${cross_prefix}gcc -print-sysroot)

kernel_repo=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
kernel_tag=v5.15.163
kernel_dir=$outdir/linux-stable

busybox_ver=1_33_1
busybox_repo=https://busybox.net/git/busybox.git
busybox_dir=$outdir/busybox

rootfs=$outdir/rootfs

copy_lib() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

copy_deps() {
  local bin="$1"

  local interp
  interp=$(${cross_prefix}readelf -a "$bin" 2>/dev/null | awk '/program interpreter/ {gsub(/\[|\]/,"",$NF); print $NF; exit}')
  if [ -n "${interp:-}" ]; then
    copy_lib "$sysroot/$interp" "$rootfs/$interp"
  fi

  ${cross_prefix}readelf -d "$bin" 2>/dev/null \
    | awk '/NEEDED/ {gsub(/\[|\]/,"",$NF); print $NF}' \
    | while read -r lib; do
        if [ -e "$sysroot/lib/$lib" ]; then
          copy_lib "$sysroot/lib/$lib" "$rootfs/lib/$lib"
        elif [ -e "$sysroot/usr/lib/$lib" ]; then
          copy_lib "$sysroot/usr/lib/$lib" "$rootfs/usr/lib/$lib"
        fi
      done
}

echo "outdir: $outdir"
echo "sysroot: $sysroot"

########################################
# 1) kernel build
########################################
if [ ! -d "$kernel_dir/.git" ]; then
  rm -rf "$kernel_dir"
  git clone --depth 1 --branch "$kernel_tag" "$kernel_repo" "$kernel_dir"
else
  cd "$kernel_dir"
  git fetch --depth 1 origin "refs/tags/$kernel_tag:refs/tags/$kernel_tag" || true
  git checkout "$kernel_tag"
fi

cd "$kernel_dir"
make ARCH=$arch CROSS_COMPILE=$cross_prefix mrproper
make ARCH=$arch CROSS_COMPILE=$cross_prefix defconfig
make -j"$(nproc)" ARCH=$arch CROSS_COMPILE=$cross_prefix Image

cp -a "$kernel_dir/arch/arm64/boot/Image" "$outdir/Image"

########################################
# 2) rootfs staging
########################################
rm -rf "$rootfs"
mkdir -p "$rootfs"
cd "$rootfs"

mkdir -p bin sbin etc proc sys dev tmp usr/bin usr/sbin var home lib usr/lib
chmod 1777 tmp

########################################
# 3) busybox build + install
########################################
if [ ! -d "$busybox_dir/.git" ]; then
  rm -rf "$busybox_dir"
  git clone "$busybox_repo" "$busybox_dir"
fi

cd "$busybox_dir"
git checkout "$busybox_ver" || true

make distclean
make defconfig
make -j"$(nproc)" ARCH=$arch CROSS_COMPILE=$cross_prefix
make ARCH=$arch CROSS_COMPILE=$cross_prefix CONFIG_PREFIX="$rootfs" install

########################################
# 4) add libraries needed by busybox
########################################
copy_deps "$rootfs/bin/busybox"

########################################
# 5) device nodes
########################################
sudo mknod -m 666 "$rootfs/dev/null" c 1 3 || true
sudo mknod -m 600 "$rootfs/dev/console" c 5 1 || true

########################################
# 6) build writer (assignment2) and place into /home
########################################
repo_root=$(cd "$(dirname "$0")/.." && pwd)
finder_app_dir="$repo_root/finder-app"

writer_src=""
if [ -f "$finder_app_dir/writer.c" ]; then
  writer_src="$finder_app_dir/writer.c"
elif [ -f "$repo_root/writer.c" ]; then
  writer_src="$repo_root/writer.c"
fi

if [ -z "$writer_src" ]; then
  echo "writer.c not found (expected finder-app/writer.c)."
  exit 1
fi

${cross_prefix}gcc -Wall -Werror -O2 -o "$rootfs/home/writer" "$writer_src"

########################################
# 7) copy required scripts/files into /home
########################################
mkdir -p "$rootfs/home/conf"

if [ -f "$finder_app_dir/finder.sh" ]; then
  cp -a "$finder_app_dir/finder.sh" "$rootfs/home/finder.sh"
elif [ -f "$repo_root/finder.sh" ]; then
  cp -a "$repo_root/finder.sh" "$rootfs/home/finder.sh"
else
  echo "finder.sh not found"
  exit 1
fi

if [ -f "$finder_app_dir/finder-test.sh" ]; then
  cp -a "$finder_app_dir/finder-test.sh" "$rootfs/home/finder-test.sh"
elif [ -f "$repo_root/finder-test.sh" ]; then
  cp -a "$repo_root/finder-test.sh" "$rootfs/home/finder-test.sh"
else
  echo "finder-test.sh not found"
  exit 1
fi

if [ -f "$finder_app_dir/autorun-qemu.sh" ]; then
  cp -a "$finder_app_dir/autorun-qemu.sh" "$rootfs/home/autorun-qemu.sh"
elif [ -f "$repo_root/autorun-qemu.sh" ]; then
  cp -a "$repo_root/autorun-qemu.sh" "$rootfs/home/autorun-qemu.sh"
fi

if [ -f "$finder_app_dir/conf/username.txt" ]; then
  cp -a "$finder_app_dir/conf/username.txt" "$rootfs/home/conf/username.txt"
elif [ -f "$repo_root/conf/username.txt" ]; then
  cp -a "$repo_root/conf/username.txt" "$rootfs/home/conf/username.txt"
else
  echo "conf/username.txt not found"
  exit 1
fi

if [ -f "$finder_app_dir/conf/assignment.txt" ]; then
  cp -a "$finder_app_dir/conf/assignment.txt" "$rootfs/home/conf/assignment.txt"
elif [ -f "$repo_root/conf/assignment.txt" ]; then
  cp -a "$repo_root/conf/assignment.txt" "$rootfs/home/conf/assignment.txt"
else
  echo "conf/assignment.txt not found"
  exit 1
fi

chmod +x "$rootfs/home/finder.sh" "$rootfs/home/finder-test.sh" "$rootfs/home/autorun-qemu.sh" 2>/dev/null || true

########################################
# 8) patch finder-test.sh path (../conf -> conf)
########################################
sed -i 's#\.\./conf/assignment\.txt#conf/assignment.txt#g' "$rootfs/home/finder-test.sh"

########################################
# 9) create initramfs
########################################
cd "$rootfs"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$outdir/initramfs.cpio.gz"

echo "done."
echo "kernel:   $outdir/Image"
echo "initramfs: $outdir/initramfs.cpio.gz"
echo "rootfs:   $rootfs"

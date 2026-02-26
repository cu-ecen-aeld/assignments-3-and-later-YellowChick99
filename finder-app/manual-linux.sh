#!/bin/bash
set -euo pipefail

outdir=${1:-/tmp/aeld}
outdir=$(realpath "$outdir")
mkdir -p "$outdir"

arch=arm64
cross_prefix=aarch64-none-linux-gnu-
sysroot=$(${cross_prefix}gcc -print-sysroot)

kernel_repo=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
kernel_tag=v5.15.163
kernel_dir=$outdir/linux-stable

busybox_repo=https://git.busybox.net/busybox/
busybox_dir=$outdir/busybox
busybox_branch=1_33_stable

rootfs=$outdir/rootfs
log="$outdir/manual-linux.log"

exec > >(tee -a "$log") 2>&1

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

ensure_kernel() {
  if [ ! -d "$kernel_dir/.git" ]; then
    rm -rf "$kernel_dir"
    git clone --depth 1 --branch "$kernel_tag" "$kernel_repo" "$kernel_dir"
  else
    cd "$kernel_dir"
    git fetch --depth 1 origin "refs/tags/$kernel_tag:refs/tags/$kernel_tag" || true
    git checkout "$kernel_tag" || true
  fi

  if [ -f "$outdir/Image" ]; then
    return 0
  fi

  cd "$kernel_dir"
  make ARCH=$arch CROSS_COMPILE=$cross_prefix mrproper
  make ARCH=$arch CROSS_COMPILE=$cross_prefix defconfig
  make -j"$(nproc)" ARCH=$arch CROSS_COMPILE=$cross_prefix Image
  cp -a "$kernel_dir/arch/arm64/boot/Image" "$outdir/Image"
}

ensure_busybox_rootfs() {
  if [ ! -d "$busybox_dir/.git" ]; then
    rm -rf "$busybox_dir"
    git clone "$busybox_repo" "$busybox_dir"
  fi

  cd "$busybox_dir"
  git fetch --all --prune || true
  git checkout "$busybox_branch" 2>/dev/null || git checkout "remotes/origin/$busybox_branch"

  if [ -d "$rootfs" ] && [ -x "$rootfs/bin/busybox" ]; then
    return 0
  fi

  rm -rf "$rootfs"
  mkdir -p "$rootfs"
  mkdir -p "$rootfs"/{bin,sbin,etc,proc,sys,dev,tmp,usr/bin,usr/sbin,var,home,lib,usr/lib}
  chmod 1777 "$rootfs/tmp"

  make distclean
  make defconfig
  make -j"$(nproc)" ARCH=$arch CROSS_COMPILE=$cross_prefix
  make ARCH=$arch CROSS_COMPILE=$cross_prefix CONFIG_PREFIX="$rootfs" install

  copy_deps "$rootfs/bin/busybox"

  if [ ! -e "$rootfs/dev/null" ]; then
    sudo mknod -m 666 "$rootfs/dev/null" c 1 3 2>/dev/null || mknod -m 666 "$rootfs/dev/null" c 1 3 2>/dev/null || true
  fi
  if [ ! -e "$rootfs/dev/console" ]; then
    sudo mknod -m 600 "$rootfs/dev/console" c 5 1 2>/dev/null || mknod -m 600 "$rootfs/dev/console" c 5 1 2>/dev/null || true
  fi
}

install_app_and_scripts() {
  local repo_root
  repo_root=$(cd "$(dirname "$0")/.." && pwd)
  local finder_app_dir="$repo_root/finder-app"

  mkdir -p "$rootfs/home/conf"

  local writer_src=""
  if [ -f "$finder_app_dir/writer.c" ]; then
    writer_src="$finder_app_dir/writer.c"
  elif [ -f "$repo_root/writer.c" ]; then
    writer_src="$repo_root/writer.c"
  fi
  if [ -z "$writer_src" ]; then
    exit 1
  fi
  ${cross_prefix}gcc -Wall -Werror -O2 -o "$rootfs/home/writer" "$writer_src"

  cp -a "$finder_app_dir/finder.sh" "$rootfs/home/finder.sh"
  cp -a "$finder_app_dir/finder-test.sh" "$rootfs/home/finder-test.sh"
  [ -f "$finder_app_dir/autorun-qemu.sh" ] && cp -a "$finder_app_dir/autorun-qemu.sh" "$rootfs/home/autorun-qemu.sh" || true
  cp -a "$finder_app_dir/conf/username.txt" "$rootfs/home/conf/username.txt"
  cp -a "$finder_app_dir/conf/assignment.txt" "$rootfs/home/conf/assignment.txt"

  chmod +x "$rootfs/home/finder.sh" "$rootfs/home/finder-test.sh" 2>/dev/null || true
  [ -f "$rootfs/home/autorun-qemu.sh" ] && chmod +x "$rootfs/home/autorun-qemu.sh" 2>/dev/null || true

  sed -i 's#\.\./conf/assignment\.txt#conf/assignment.txt#g' "$rootfs/home/finder-test.sh"
}

make_initramfs() {
  rm -f "$outdir/initramfs.cpio" "$outdir/initramfs.cpio.gz" "$outdir/filelist.bin"
  cd "$rootfs"
  find . -print0 > "$outdir/filelist.bin"
  cpio --null -ov --format=newc < "$outdir/filelist.bin" > "$outdir/initramfs.cpio"
  gzip -9 -f "$outdir/initramfs.cpio"
  test -f "$outdir/initramfs.cpio.gz"
}

ensure_kernel
ensure_busybox_rootfs
install_app_and_scripts

if [ ! -f "$outdir/initramfs.cpio.gz" ]; then
  make_initramfs
fi

echo "$outdir/Image"
echo "$outdir/initramfs.cpio.gz"

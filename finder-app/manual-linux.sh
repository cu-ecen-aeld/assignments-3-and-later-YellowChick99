#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# manual-linux.sh
# Builds:
#   - Linux kernel Image (arch/arm64/boot/Image)  -> ${OUTDIR}/Image
#   - Rootfs (BusyBox-based) in                  -> ${OUTDIR}/rootfs
#   - initramfs.cpio.gz                          -> ${OUTDIR}/initramfs.cpio.gz
#
# Usage:
#   ./manual-linux.sh [outdir]
#   default outdir: /tmp/aeld
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${1:-/tmp/aeld}"

# Make OUTDIR absolute
mkdir -p "$OUTDIR" || { echo "ERROR: cannot create outdir: $OUTDIR"; exit 1; }
OUTDIR="$(cd "$OUTDIR" && pwd)"

echo "Using OUTDIR: $OUTDIR"

# Toolchain / arch settings (AArch64)
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

# Kernel settings
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_TAG="v5.15.163"   # 과제/강의에서 지정된 tag가 따로 있으면 여기만 바꾸면 됨
KERNEL_SRC="${OUTDIR}/linux-stable"

# BusyBox settings
BUSYBOX_REPO="https://git.busybox.net/busybox/"
BUSYBOX_TAG="1_33_1"     # 강의/과제에서 다른 버전 쓰면 바꿔도 됨
BUSYBOX_SRC="${OUTDIR}/busybox"

ROOTFS="${OUTDIR}/rootfs"

# ------------------------------------------------------------
# helper: install packages (optional)
# ------------------------------------------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: required command not found: $1"; exit 1; }
}

need_cmd git
need_cmd make
need_cmd gcc || true
need_cmd cpio
need_cmd gzip
need_cmd find
need_cmd sed

# Cross compiler check
if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
  echo "ERROR: cross compiler not found: ${CROSS_COMPILE}gcc"
  echo "       install aarch64-none-linux-gnu toolchain and ensure it's in PATH."
  exit 1
fi

# ------------------------------------------------------------
# 1) Fetch kernel source (depth 1, tag checkout)
# ------------------------------------------------------------
if [ ! -d "$KERNEL_SRC" ]; then
  echo "Cloning Linux kernel ($KERNEL_TAG) into $KERNEL_SRC"
  git clone --depth 1 --branch "$KERNEL_TAG" "$KERNEL_REPO" "$KERNEL_SRC"
else
  echo "Kernel source exists: $KERNEL_SRC"
  # ensure correct tag checked out
  ( cd "$KERNEL_SRC"
    git fetch --depth 1 origin "refs/tags/${KERNEL_TAG}:refs/tags/${KERNEL_TAG}" || true
    git checkout -f "$KERNEL_TAG"
  )
fi

# ------------------------------------------------------------
# 2) Build kernel Image
# ------------------------------------------------------------
echo "Building kernel Image..."
(
  cd "$KERNEL_SRC"
  make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" mrproper
  make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
  make -j"$(nproc)" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" Image
)

# Copy Image to OUTDIR
VMLINUX_IMAGE="${KERNEL_SRC}/arch/${ARCH}/boot/Image"
if [ ! -f "$VMLINUX_IMAGE" ]; then
  echo "ERROR: kernel Image not found at $VMLINUX_IMAGE"
  exit 1
fi
cp -f "$VMLINUX_IMAGE" "${OUTDIR}/Image"
echo "Kernel Image -> ${OUTDIR}/Image"

# ------------------------------------------------------------
# 3) Create/clean rootfs staging
# ------------------------------------------------------------
echo "Preparing rootfs at ${ROOTFS}"
sudo rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

# Required dirs
mkdir -p "${ROOTFS}"/{bin,sbin,etc,proc,sys,dev,lib,lib64,tmp,var,usr/{bin,sbin,lib},home}

# ------------------------------------------------------------
# 4) Fetch & build BusyBox (static)
# ------------------------------------------------------------
if [ ! -d "$BUSYBOX_SRC" ]; then
  echo "Cloning BusyBox ($BUSYBOX_TAG) into $BUSYBOX_SRC"
  git clone --depth 1 --branch "$BUSYBOX_TAG" "$BUSYBOX_REPO" "$BUSYBOX_SRC"
else
  echo "BusyBox source exists: $BUSYBOX_SRC"
  ( cd "$BUSYBOX_SRC"
    git fetch --depth 1 origin "refs/tags/${BUSYBOX_TAG}:refs/tags/${BUSYBOX_TAG}" || true
    git checkout -f "$BUSYBOX_TAG"
  )
fi

echo "Building BusyBox (static)..."
(
  cd "$BUSYBOX_SRC"
  make distclean
  make defconfig

  # Enable static build: CONFIG_STATIC=y
  sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config || true

  make -j"$(nproc)" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"
  make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CONFIG_PREFIX="$ROOTFS" install
)

# ------------------------------------------------------------
# 5) Device nodes (needs sudo)
# ------------------------------------------------------------
echo "Creating device nodes..."
sudo mknod -m 666 "${ROOTFS}/dev/null" c 1 3 || true
sudo mknod -m 600 "${ROOTFS}/dev/console" c 5 1 || true

# ------------------------------------------------------------
# 6) /init script (for initramfs boot)
# ------------------------------------------------------------
echo "Creating /init..."
cat > "${ROOTFS}/init" << 'EOF'
#!/bin/sh
set -e

mount -t proc none /proc
mount -t sysfs none /sys

# devtmpfs might not be available; ignore if fails
mount -t devtmpfs none /dev 2>/dev/null || true

echo
echo "======================================"
echo " AESD QEMU booted (initramfs) "
echo "======================================"
echo

cd /home
exec /bin/sh
EOF
chmod +x "${ROOTFS}/init"

# ------------------------------------------------------------
# 7) Cross-compile writer (assignment2) and copy into /home
# ------------------------------------------------------------
echo "Cross-compiling writer..."
# writer.c is typically in finder-app/
if [ -f "${SCRIPT_DIR}/writer.c" ]; then
  "${CROSS_COMPILE}gcc" -Wall -Werror -O2 -o "${OUTDIR}/writer" "${SCRIPT_DIR}/writer.c"
  cp -f "${OUTDIR}/writer" "${ROOTFS}/home/writer"
  chmod +x "${ROOTFS}/home/writer"
else
  echo "WARNING: writer.c not found in ${SCRIPT_DIR}. Skipping writer build."
fi

# ------------------------------------------------------------
# 8) Copy finder scripts & conf into /home
# ------------------------------------------------------------
echo "Copying scripts and conf to /home..."
# assignment2 scripts in finder-app
for f in finder.sh finder-test.sh finder-test.sh; do
  if [ -f "${SCRIPT_DIR}/${f}" ]; then
    cp -f "${SCRIPT_DIR}/${f}" "${ROOTFS}/home/${f}"
  fi
done

# conf files in ../conf
if [ -f "${SCRIPT_DIR}/../conf/username.txt" ]; then
  cp -f "${SCRIPT_DIR}/../conf/username.txt" "${ROOTFS}/home/username.txt"
fi
if [ -f "${SCRIPT_DIR}/../conf/assignment.txt" ]; then
  cp -f "${SCRIPT_DIR}/../conf/assignment.txt" "${ROOTFS}/home/assignment.txt"
fi

# also copy finder-test.sh dependency scripts mentioned
# (요구사항: finder.sh, conf/username.txt, conf/assignment.txt, finder-test.sh)
# 여기서는 conf를 home에 username.txt/assignment.txt로 두지만,
# 요구사항대로 "conf/assignment.txt" 경로를 쓰려면 /home/conf 로 옮기는게 안전.
mkdir -p "${ROOTFS}/home/conf"
if [ -f "${SCRIPT_DIR}/../conf/username.txt" ]; then
  cp -f "${SCRIPT_DIR}/../conf/username.txt" "${ROOTFS}/home/conf/username.txt"
fi
if [ -f "${SCRIPT_DIR}/../conf/assignment.txt" ]; then
  cp -f "${SCRIPT_DIR}/../conf/assignment.txt" "${ROOTFS}/home/conf/assignment.txt"
fi

# Copy finder-test.sh and patch its path: ../conf/assignment.txt -> conf/assignment.txt
if [ -f "${ROOTFS}/home/finder-test.sh" ]; then
  sed -i 's|\.\./conf/assignment\.txt|conf/assignment.txt|g' "${ROOTFS}/home/finder-test.sh"
  chmod +x "${ROOTFS}/home/finder-test.sh"
fi

# Ensure finder.sh is executable and uses /bin/sh (busybox friendly)
if [ -f "${ROOTFS}/home/finder.sh" ]; then
  chmod +x "${ROOTFS}/home/finder.sh"
  # if it uses /bin/bash, replace to /bin/sh
  sed -i '1s|^#! */bin/bash|#!/bin/sh|' "${ROOTFS}/home/finder.sh" || true
fi

# ------------------------------------------------------------
# 9) Copy autorun-qemu.sh into /home
# ------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/autorun-qemu.sh" ]; then
  cp -f "${SCRIPT_DIR}/autorun-qemu.sh" "${ROOTFS}/home/autorun-qemu.sh"
  chmod +x "${ROOTFS}/home/autorun-qemu.sh"
fi

# ------------------------------------------------------------
# 10) Create initramfs.cpio.gz
# ------------------------------------------------------------
echo "Creating initramfs..."
(
  cd "$ROOTFS"
  find . -print0 \
    | cpio --null -ov --format=newc --owner root:root \
    > "${OUTDIR}/initramfs.cpio"
)
gzip -f "${OUTDIR}/initramfs.cpio"
mv -f "${OUTDIR}/initramfs.cpio.gz" "${OUTDIR}/initramfs.cpio.gz"

echo "Initramfs -> ${OUTDIR}/initramfs.cpio.gz"
echo "DONE."


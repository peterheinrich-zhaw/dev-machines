#!/bin/bash
set -e

SRC_DIR="./src"
CONF_IMG="./build/config.img"
CACHE_IMG="./build/cache.qcow2"
HOME_IMG="./build/home.qcow2"
TMP_IMG="./build/tmp.qcow2"

APKOVL_FILE="localhost.apkovl.tar.gz"

ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/alpine-standard-3.24.0-aarch64.iso"
ISO_SHA256="1ae10a3fa93e083000cd3f581ece1a0c9690c363901f49fcedfeaf5c3fbf03dc"
ISO_PATH="./download/alpine-standard-3.24.0-aarch64.iso"
UEFI_PKG_URL="http://ftp.ch.debian.org/debian/pool/main/e/edk2/qemu-efi-aarch64_2022.11-6+deb12u2_all.deb"
UEFI_PKG_PATH="./download/qemu-efi-aarch64_2022.11-6+deb12u2_all.deb"
UEFI_IMG_NAME="./download/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
UEFI_VAR_NAME=QEMU_VARS.fd

mkdir -p build
mkdir -p download

if [ ! -f $UEFI_IMG_NAME ]; then
    curl -o $UEFI_PKG_PATH $UEFI_PKG_URL
    cd download
    ar -xv ../$UEFI_PKG_PATH
    tar xf data.tar.xz
    rm -f debian-binary data.tar.xz control.tar.xz
    cd ..
    truncate -s 64M $UEFI_IMG_NAME
fi

if [ ! -f $ISO_PATH ]; then
    curl -o $ISO_PATH $ISO_URL
fi

if echo "$ISO_SHA256  $ISO_PATH" | shasum -a 256 -c --status; then
    echo "SHA256 sum of $ISO_PATH ok."
else
    echo "Error: SHA256 sum mismatch or file missing! Delete ISO file if incomplete/damaged."
    exit 1
fi

if [ ! -f $CONF_IMG ]; then

    tar -czf $APKOVL_FILE --owner=root --group=root -C "$SRC_DIR" etc home

    dd if=/dev/zero of="$CONF_IMG" bs=1m count=32 status=none

    DEV=$(hdiutil attach -nomount "$CONF_IMG" | awk '{print $1}')
    newfs_msdos -v "ALPINE" "$DEV" > /dev/null

    MOUNT_POINT=$(mktemp -d /tmp/alpine-mount.XXXXXX)
    mount -t msdos "$DEV" "$MOUNT_POINT"
    
    cp $APKOVL_FILE "$MOUNT_POINT/"
    umount "$MOUNT_POINT"
    hdiutil detach "$DEV" > /dev/null

    rm -f $APKOVL_FILE

    if [[ -n "$MOUNT_POINT" && "$MOUNT_POINT" == /tmp/* ]]; then
        rmdir "$MOUNT_POINT"
    else
        echo "Error: Refusing to delete unsafe mount point path: '$MOUNT_POINT'" >&2
        exit 1
    fi
fi

if [ ! -f $CACHE_IMG ]; then
    qemu-img create -f qcow2 $CACHE_IMG 5G > /dev/null
fi

if [ ! -f $HOME_IMG ]; then
    qemu-img create -f qcow2 $HOME_IMG 10G > /dev/null
fi

if [ ! -f $TMP_IMG ]; then
    qemu-img create -f qcow2 $TMP_IMG 10G > /dev/null
fi

qemu-system-aarch64 \
  -machine virt,highmem=on \
  -cpu host \
  -accel hvf \
  -smp 4 \
  -m 8192 \
  -drive if=pflash,format=raw,readonly=on,file=$UEFI_IMG_NAME \
  -drive if=virtio,format=raw,file="$CONF_IMG",if=virtio,index=0 \
  -drive if=virtio,format=qcow2,file="$CACHE_IMG",if=virtio,index=1 \
  -drive if=virtio,format=qcow2,file="$HOME_IMG",if=virtio,index=2 \
  -drive if=virtio,format=qcow2,file="$TMP_IMG",if=virtio,index=3 \
  -drive file="$ISO_PATH",format=raw,if=virtio,index=4,readonly=on\
  -boot e \
  -device virtio-gpu-pci \
  -display cocoa\
  -device qemu-xhci,id=usb-bus \
  -device usb-kbd,bus=usb-bus.0 \
  -device usb-tablet,bus=usb-bus.0 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0 \
  -device intel-hda \
  -device hda-duplex $1


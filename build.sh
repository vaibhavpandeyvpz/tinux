#!/usr/bin/env bash

WD=`pwd`

abort() {
    echo $1
    exit 1
}

help() {
    echo 'tinux/build.sh (0.0.1)'
    echo
    echo 'Using Tinux, you can build your very own, tiny (Busybox based)'
    echo 'Linux distribution. To run it, follow below e.g.,'
    echo
    echo '  ./build.sh <kernel-version> <busybox-version>'
    echo '  ./build.sh 5.0.0 1.30.0'
    exit 1
}

if [[ "$#" -lt 2 ]]; then
    help
fi

CACHE="$HOME/.cache/tinux"
mkdir -p "$CACHE"

KERNEL=$1
KERNEL_MAJOR="${KERNEL:0:1}"
KERNEL_ARCHIVE=linux-$KERNEL.tar.xz
KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v$KERNEL_MAJOR.x/$KERNEL_ARCHIVE
KERNEL_SOURCE="$WD/source/kernel"
KERNEL_BUILD="$WD/build/kernel"

BUSYBOX=$2
BUSYBOX_ARCHIVE=busybox-$BUSYBOX.tar.bz2
BUSYBOX_URL=https://busybox.net/downloads/$BUSYBOX_ARCHIVE
BUSYBOX_SOURCE="$WD/source/busybox"
BUSYBOX_BUILD="$WD/build/busybox"

INITRAMFS_BUILD="$WD/build/initramfs"

THREADS=$(nproc --all)
echo "Downloading (if required) and extracting kernel $KERNEL..."
if [[ ! -f "$CACHE/$KERNEL_ARCHIVE" ]]; then
    echo Downloading $KERNEL_ARCHIVE...
    wget -O "$CACHE/$KERNEL_ARCHIVE" $KERNEL_URL || abort "Could not download $KERNEL_URL."
fi
if [[ -d "$KERNEL_SOURCE" ]]; then
    rm -rf "$KERNEL_SOURCE"
fi
mkdir -p "$KERNEL_SOURCE"
tar -xf "$CACHE/$KERNEL_ARCHIVE" -C "$KERNEL_SOURCE" --strip 1 || abort "Could not extract $CACHE/$KERNEL_ARCHIVE."

echo "Downloading (if required) and extracting busybox $BUSYBOX..."
if [[ ! -f "$CACHE/$BUSYBOX_ARCHIVE" ]]; then
    echo Downloading $BUSYBOX_ARCHIVE...
    wget -O "$CACHE/$BUSYBOX_ARCHIVE" $BUSYBOX_URL || abort "Could not download $BUSYBOX_URL."
fi
if [[ -d "$BUSYBOX_SOURCE" ]]; then
    rm -rf "$BUSYBOX_SOURCE"
fi
mkdir -p "$BUSYBOX_SOURCE"
tar -xf "$CACHE/$BUSYBOX_ARCHIVE" -C "$BUSYBOX_SOURCE" --strip 1 || abort "Could not extract $CACHE/$BUSYBOX_ARCHIVE."

rm -rf "$WD/build"

echo Building kernel $KERNEL using $THREADS threads...
mkdir -p "$KERNEL_BUILD"
cd "$KERNEL_SOURCE"
make O="$KERNEL_BUILD" defconfig
cd "$KERNEL_BUILD"
# Ensure initramfs/initrd support is enabled
CONFIG_CHANGED=0
if ! grep -q "^CONFIG_BLK_DEV_INITRD=y" .config; then
    sed -i 's/# CONFIG_BLK_DEV_INITRD is not set/CONFIG_BLK_DEV_INITRD=y/' .config 2>/dev/null || \
        echo "CONFIG_BLK_DEV_INITRD=y" >> .config
    CONFIG_CHANGED=1
fi
# Ensure gzip decompression support for compressed initramfs
if ! grep -q "^CONFIG_RD_GZIP=y" .config; then
    sed -i 's/# CONFIG_RD_GZIP is not set/CONFIG_RD_GZIP=y/' .config 2>/dev/null || \
        echo "CONFIG_RD_GZIP=y" >> .config
    CONFIG_CHANGED=1
fi
read -p "Would you like to customize kernel build config? (yN) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    make menuconfig
    CONFIG_CHANGED=1
fi
# Rebuild kernel if config was changed
if [ $CONFIG_CHANGED -eq 1 ]; then
    echo "Kernel config changed, rebuilding..."
    make olddefconfig
fi
make -j$THREADS
# Copy kernel image (x86_64 builds to arch/x86/boot/bzImage)
if [ -f "$KERNEL_BUILD/arch/x86/boot/bzImage" ]; then
    cp "$KERNEL_BUILD/arch/x86/boot/bzImage" "$WD/build/"
else
    # Fallback: try to find bzImage
    cp "$KERNEL_BUILD/arch/"*"/boot/bzImage" "$WD/build/" 2>/dev/null || \
    abort "Could not find kernel image (bzImage)"
fi

echo Building busybox $BUSYBOX using $THREADS threads...
mkdir -p "$BUSYBOX_BUILD"
cd "$BUSYBOX_SOURCE"
make O="$BUSYBOX_BUILD" defconfig
cd "$BUSYBOX_BUILD"
sed -i -e "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" .config
read -p "Would you like to customize busybox build config? (yN) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    make menuconfig
fi
make -j$THREADS
make install

echo Building ramdisk...
if [[ -d "$INITRAMFS_BUILD" ]]; then
    rm -rf "$INITRAMFS_BUILD"
fi
mkdir -p "$INITRAMFS_BUILD"
cd "$INITRAMFS_BUILD"
mkdir -p dev etc/init.d proc sys
cp -a "$BUSYBOX_BUILD/_install/"* .
rm linuxrc
echo "#!/bin/sh

dmesg -n 1
clear

mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys

mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

cat <<!

System startup took \$(cut -d' ' -f1 /proc/uptime) seconds.

   ▄▄▄▄▀ ▄█    ▄     ▄       ▄  
▀▀▀ █    ██     █     █  ▀▄   █ 
    █    ██ ██   █ █   █   █ ▀  
   █     ▐█ █ █  █ █   █  ▄ █   
  ▀       ▐ █  █ █ █▄ ▄█ █   ▀▄ 
            █   ██  ▀▀▀   ▀     

Tinux/0.0.1

!" > etc/init.d/rcS
chmod +x etc/init.d/rcS
ln -s sbin/init init
chmod +x init
find . -print0 | cpio --format=newc --null --owner=root:root -o | gzip -9 > "$WD/build/initramfs.cpio.gz"

echo Build completed!
cd "$WD"

read -p "Would you like to boot using created kernel and ramdisk? (yN) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    qemu-system-x86_64 -kernel "$WD/build/bzImage" -initrd "$WD/build/initramfs.cpio.gz" -append "console=ttyS0" -nographic
fi

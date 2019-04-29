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
read -p "Would you like to customize kernel build config? (yN) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    make menuconfig
fi
make -j$THREADS
cp "$KERNEL_BUILD/arch/"*"/boot/bzImage" "$WD/build/"

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

mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t sysfs none /sys

mkdir -p /dev/pts
mount -t devpts none /dev/pts

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

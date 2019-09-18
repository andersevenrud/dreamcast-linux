#!/bin/bash
#
# Dreamcast Linux build script
# Author: Anders Evenrud <andersevenrud@gmail.com>
#
set -e

# FIXME: Optimize the staging of GCC and libc. This can be done with newlib probably.
# TODO: Patch TTYs in busybox
# TODO: Create a new version of the roaster that creates ISO, not burn directly

# Customize these to your liking
GNU_MIRROR="https://gnuftp.uib.no"
MY_COPTS="-j4"

# Dependencies
BINUTILS_VERSION="2.32"
GCC_VERSION="8.3.0"
GLIBC_VERSION="2.30"
LINUX_VERSION="5.2"
BUSYBOX_VERSION="1.31.0"

# Globals
export TARGET="sh4-linux"
export PREFIX="/opt/dreamcast"
export PATH="${PATH}:${PREFIX}/bin"
export INITRD=`pwd`/initrd

# Preparations
mkdir -p /opt/build

# Build
pushd dreamcast

  #
  # Sources
  #

  if [ ! -f "binutils-${BINUTILS_VERSION}.tar.xz" ]; then
    wget ${GNU_MIRROR}/binutils/binutils-${BINUTILS_VERSION}.tar.xz
    tar xJf binutils-${BINUTILS_VERSION}.tar.xz
  fi

  if [ ! -f "gcc-${GCC_VERSION}.tar.xz" ]; then
    wget ${GNU_MIRROR}/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    tar xJf gcc-${GCC_VERSION}.tar.xz
  fi

  if [ ! -f "glibc-${GLIBC_VERSION}.tar.xz" ]; then
    wget ${GNU_MIRROR}/glibc/glibc-${GLIBC_VERSION}.tar.xz
    tar xJf glibc-${GLIBC_VERSION}.tar.xz
  fi

  if [ ! -f "v${LINUX_VERSION}.tar.gz" ]; then
    wget https://github.com/torvalds/linux/archive/v${LINUX_VERSION}.tar.gz
    tar xzf v${LINUX_VERSION}.tar.gz
  fi

  if [ ! -f "busybox-${BUSYBOX_VERSION}.tar.bz2" ]; then
    wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
    tar xjf busybox-${BUSYBOX_VERSION}.tar.bz2
  fi

  if [ ! -d "sh-boot" ]; then
    tar xzf ../sh-boot-20010831-1455.tar.gz
    patch -p0 < ../sh-boot-20010831-1455.diff
    patch -p0 < ../sh-boot-20010831-1455-sh4.diff
  fi

  #
  # Preparations
  #

  mkdir -p build-binutils build-gcc build-glibc initrd

  #
  # Binutils
  #

  pushd build-binutils
    ../binutils-${BINUTILS_VERSION}/configure \
      --target=$TARGET \
      --prefix=$PREFIX
    make ${MY_COPTS}
    make install
  popd

  #
  # Kernel headers
  #

  pushd linux-${LINUX_VERSION}
    cp ../../kernel.config .config
    make ARCH=sh CROSS_COMPILE=sh4-linux- headers_install
    if [ ! -d "${PREFIX}/${TARGET}/include" ]; then
      mkdir -p ${PREFIX}/${TARGET}/include
      cp -r usr/include/* ${PREFIX}/${TARGET}/include
    fi
  popd

  #
  # GCC stage 1
  #

  pushd build-gcc
    ../gcc-${GCC_VERSION}/configure \
      --target=$TARGET \
      --prefix=$PREFIX \
      --with-multilib-list=m4,m4-nofpu \
      --enable-languages=c,c++
    make ${MY_COPTS} all-gcc
    make install-gcc
  popd

  #
  # Glibc
  #

  pushd build-glibc
    ../glibc-${GLIBC_VERSION}/configure \
      --host=$TARGET \
      --prefix=${PREFIX}/${TARGET} \
      --disable-debug \
      --disable-profile \
      --disable-sanity-checks \
      --build=$MACHTYPE \
      --with-headers=${PREFIX}/${TARGET}/include

    make install-bootstrap-headers=yes install-headers

    make csu/subdir_lib
    install csu/crt1.o csu/crti.o csu/crtn.o ${PREFIX}/${TARGET}/lib
    sh4-linux-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o ${PREFIX}/${TARGET}/lib/libc.so
    mkdir -p ${PREFIX}/${TARGET}/include/gnu
    touch ${PREFIX}/${TARGET}/include/gnu/stubs.h
  popd

  pushd build-gcc
    make ${MY_COPTS} all-target-libgcc
    make install-target-libgcc
  popd

  pushd build-glibc
    make ${MY_COPTS}
    make install
  popd

  #
  # GCC stage 2
  #

  pushd build-gcc
    make ${MY_COPTS} all
    make install
  popd

  #
  # Linux kernel
  #

  pushd linux-${LINUX_VERSION}
    make ARCH=sh CROSS_COMPILE=sh4-linux- clean zImage
  popd

  #
  # Busybox
  #

  pushd busybox-${BUSYBOX_VERSION}
    cp ../../busybox.config .config

    make CROSS=sh4-linux- \
      DOSTATIC=true \
      CFLAGS_EXTRA="-I ${PREFIX}/${TARGET}/include" \
      PREFIX=${INITRD} \
      clean all install
  popd

  #
  # Linux ramdisk
  #

  if [ ! -d "${INITRD}/dev" ]; then
    mkdir -p ${INITRD}/dev
    mknod ${INITRD}/dev/console c 5 1
  fi

  if [ ! -f "initrd.bin" ]; then
    dd if=/dev/zero of=initrd.img bs=1k count=4096
    mke2fs -F -vm0 initrd.img
    mkdir initrd.dir
    mount -o loop initrd.img initrd.dir
    (cd initrd ; tar cf - .) | (cd initrd.dir ; tar xvf -)
    umount initrd.dir
    gzip -c -9 initrd.img > initrd.bin
  fi

  #
  # Bootloader
  #

  pushd sh-boot/tools/dreamcast
    cp ../../../linux-${LINUX_VERSION}/arch/sh/boot/zImage ./zImage.bin
    cp ../../../initrd.bin .
    make clean scramble kernel-boot.bin
  popd

  #
  # Finalize
  #

  cp sh-boot/tools/dreamcast/kernel-boot.bin /opt/build/
popd

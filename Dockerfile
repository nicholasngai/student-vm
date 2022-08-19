# This configures the OS of the builder, NOT the OS of the actual image. Adjust
# the suite/mirror of the debootstrap command to adjust that.
FROM ubuntu:22.04

WORKDIR /cs162-vm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        cpio \
        debootstrap \
        qemu-system-x86 \
        qemu-utils \
    && rm -rf /var/cache/apt/lists/*

# debootstrap a base Ubuntu system. We use --foreign here since *something* is
# causing debootstrap to fail when bootstraping an Ubuntu system from Docker
# (i.e. without privileges). I've tried fakechroot and fakechroot + fakeroot
# here, but nothing works, so we'll just bootstrap it by dumping it into QEMU
# to finish the second-stage install of --foreign.
RUN debootstrap \
    --foreign \
    --arch=amd64 \
    --components=main,restricted,universe,multiverse \
    bionic \
    root \
    http://archive.ubuntu.com/ubuntu/

# Get a kernel image and initrd for QEMU to boot to. It doesn't really matter
# what the initrd does as long as it responds to a init kernel parameter.
RUN curl -Lo vmlinuz http://deb.debian.org/debian/dists/buster/main/installer-amd64/current/images/hd-media/vmlinuz \
    && curl -Lo initrd.gz http://deb.debian.org/debian/dists/buster/main/installer-amd64/current/images/hd-media/initrd.gz

# Add an installation helper script to wrap up installation inside QEMU.
RUN mkdir initfs \
    && ( cd initfs && gzip -dc ../initrd.gz | cpio -i ) \
    && printf '#!/bin/sh\n\
\n\
set -eux \n\
\n\
modprobe ext4\n\
mkdir -p /mnt/root\n\
mount /dev/vda /mnt/root\n\
chroot /mnt/root /debootstrap/debootstrap --second-stage\n\
umount /mnt/root\n\
poweroff -f\n\
' > initfs/installer.sh \
    && chmod +x initfs/installer.sh \
    && ( cd initfs && find . | cpio -o -H newc | gzip -9 -n > ../initrd.gz ) \
    && rm -rf initfs

# Dump the current first-stage filesystem to a disk, boot QEMU and execute
# debootstrap second stage, then extract the newly installed filesystem.
RUN dd if=/dev/zero of=root.iso bs=1M count=512 \
    && mkfs.ext4 -d root root.iso \
    && qemu-system-x86_64 \
        -m 512M \
        -nographic \
        -drive if=virtio,format=raw,file=root.iso \
        -kernel vmlinuz \
        -initrd initrd.gz \
        -append 'console=ttyS0 init=/installer.sh'

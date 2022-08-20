# This configures the OS of the builder, NOT the OS of the actual image. Adjust
# the suite/mirror of the debootstrap command to adjust that.
FROM ubuntu:22.04

ARG VM_NAME=cs162-student-vm
ARG VM_IMG_RAW=$VM_NAME.img
ARG VM_IMG_QCOW2=$VM_NAME.qcow2

WORKDIR /$VM_NAME

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        debootstrap \
        qemu-system-x86 \
        qemu-utils \
        parted \
        uuid \
    && rm -rf /var/cache/apt/lists/*

#
# BASE FILESYSTEM.
#

# Debootstrap a base Ubuntu system.
RUN debootstrap \
    --arch=amd64 \
    --components=main,restricted,universe,multiverse \
    jammy \
    root \
    http://archive.ubuntu.com/ubuntu/

# Install bootloader (grub-efi-amd64-signed), kernel (linux-image-virtual), and
# init (systemd). The bootloader is installed at the very end when the disk
# image is generated.
RUN chroot root apt-get update \
    && chroot root apt-get install -y \
        grub-pc \
        linux-image-virtual \
        systemd \
        systemd-sysv

# Add fstab, networking, and hostname config.
RUN uuid > rootfs-uuid \
    && printf "\
UUID=$(cat rootfs-uuid)	/	ext4	defaults	0	1\n\
tmpfs	/tmp	tmpfs	defaults,nosuid,nodev	0	2\n\
" > root/etc/fstab \
    && printf "\
[Match]\n\
Name=en*\n\
\n\
[Network]\n\
DHCP=yes\n\
" > root/etc/systemd/network/99-wildcard.network \
    && chroot root systemctl enable systemd-networkd \
    && echo "$VM_NAME" > root/etc/hostname

#
# USER PROGRAMS AND CUSTOMIZATION.
#

# Install custom programs in rootfs.
RUN chroot root apt-get install -y \
        autoconf \
        binutils \
        clang \
        clang-format \
        cmake \
        cgdb \
        curl \
        exuberant-ctags \
        g++ \
        gcc \
        gdb \
        git \
        python3 \
        python3-pip \
        qemu-system-x86 \
        samba \
        silversearcher-ag \
        sudo \
        tmux \
        valgrind \
        vim \
        wget

#
# DISK IMAGE GENEREATION.
#

# Add an init script that will be executed as init to install the bootloader.
RUN printf '#!/bin/sh\n\
\n\
set -eux\n\
\n\
# If executing the file directly, switch to cat the file and pass it into the \
# /bin/sh command line so that the script can remove the file. \
if [ "$0" != "/bin/sh" ]; then\n\
    exec /bin/sh -c "$(cat "$0")" /bin/sh "$0"\n\
fi\n\
\n\
mount -o remount,rw /\n\
grub-install /dev/vda\n\
update-grub\n\
rm -f "$1"\n\
mount -o remount,ro /\n\
poweroff -f\n\
' > root/install-grub \
    && chmod +x root/install-grub

# Create a 2-partition (BIOS boot partition and rootfs) disk image by creating
# the images individually and merging them with dd, setting up the partition
# table to match with dd's offsets.
#
# The full image will be 8192 MiB. We allocate 1 MiB for the GPT header and 15
# MiB for the BIOS boot partition and leave 1 MiB of buffer at the end to
# safely fit the secondary partition table, so the root image will be 8175
# (8192 - 1 - 15 - 1) MiB in size.
#
# We're using shell math expressions here since parted works with MB instead of
# MiB, so we're working in sectors. There are 2048 sectors in 1 MiB, so the
# ith MiB is $(( i * 2048 )). Also, parted uses inclusive ranges, so we use
# $(( i * 2048 - 1 )) for all the end sectors.
RUN dd if=/dev/zero of="$VM_IMG_RAW".rootfs bs=1M count=8175 \
    && mkfs.ext4 -U $(cat rootfs-uuid) -d root "$VM_IMG_RAW".rootfs \
    && dd if=/dev/zero of="$VM_IMG_RAW" bs=1M count=1 \
    && dd if=/dev/zero of="$VM_IMG_RAW" bs=1M seek=1 count=15 \
    && dd if="$VM_IMG_RAW".rootfs of="$VM_IMG_RAW" bs=1M seek=16 \
    && dd if=/dev/zero of="$VM_IMG_RAW" bs=1M seek=8191 count=1 \
    && parted -s -- "$VM_IMG_RAW" \
        mklabel gpt \
        mkpart bios fat32 $(( 1 * 2048 ))s $(( 16 * 2048 - 1 ))s \
        set 1 bios_grub on \
        mkpart root ext4 $(( 16 * 2048 ))s $(( 8191 * 2048 - 1 ))s \
    && rm -f "$VM_IMG_RAW".rootfs \
# Execute the earlier-inserted install-grub script by booting the image via \
# QEMU using the rootfs's kernel and initrd. \
    && qemu-system-x86_64 \
        -m 512M \
        -nographic \
        -drive if=virtio,format=raw,file="$VM_IMG_RAW" \
        -kernel root/boot/vmlinuz \
        -initrd root/boot/initrd.img \
        -append "console=ttyS0 root=UUID=$(cat rootfs-uuid) init=/install-grub" \
    && qemu-img convert -f raw -O qcow2 "$VM_IMG_RAW" "$VM_IMG_QCOW2" \
    && rm -f "$VM_IMG_RAW"

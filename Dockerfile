# This configures the OS of the builder, NOT the OS of the actual image. Adjust
# the suite/mirror of the debootstrap command to adjust that.
FROM ubuntu:22.04

WORKDIR /cs162-vm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        debootstrap \
        qemu-system-x86 \
        qemu-utils \
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
# init (systemd).
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
    && echo 'cs162-student-vm' > root/etc/hostname

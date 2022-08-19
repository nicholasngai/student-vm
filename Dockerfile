# This configures the OS of the builder, NOT the OS of the actual image. Adjust
# the suite/mirror of the debootstrap command to adjust that.
FROM ubuntu:22.04

WORKDIR /cs162-vm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        debootstrap \
        qemu-system-x86 \
        qemu-utils \
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

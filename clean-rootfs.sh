#!/usr/bin/env bash

# Post-kiwi cleanup of the root filesystem inside a raw disk image.
# Called from Makefile.docker after kiwi has finished writing the raw
# disk (including grub2-mkconfig). Shared by the raw.xz and qcow2.xz
# build targets.
#
# Usage: ./clean-rootfs.sh /path/to/raw-disk.img

set -o errexit

RAW=$1

LOOP=$(losetup --find --show "$RAW")
kpartx -as "$LOOP"

# Find the ext4 root partition. The layout differs between amd64
# (p1=bios-boot, p2=EFI, p3=root) and arm64 (p1=EFI, p2=root).
ROOT=
for p in /dev/mapper/"$(basename "$LOOP")"p*; do
    [ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" = ext4 ] || continue
    ROOT=$p
    break
done
: ${ROOT:?Failed to find ext4 partition in $RAW}

MNT=$(mktemp -d)
mount "$ROOT" "$MNT"

# grub2 build/install tools. The EFI bootloader and runtime grub modules
# in /boot/grub2 are already in place; these commands are not invoked
# again. Keep grub2-editenv for grubenv management.
find "$MNT/usr/bin" "$MNT/usr/sbin" -maxdepth 1 -name 'grub2-*' \
    ! -name 'grub2-editenv' -delete

# Config files only read by grub2-mkconfig, which we just removed.
rm -rf "$MNT/etc/grub.d" "$MNT/etc/default/grub"

# /usr/share/grub2/<arch>-efi is the factory copy of the grub modules
# that grub2-install replicated into /boot/grub2/<arch>-efi.
rm -rf "$MNT/usr/share/grub2"/*-efi
rm -f  "$MNT/usr/share/grub2"/*.pf2
rm -rf "$MNT/usr/share/grub2/grub-mkconfig_lib" "$MNT/usr/share/grub2/themes"

sync

# Discard freed blocks so they become holes in the backing raw file.
# qemu-img and xz both benefit from this.
fstrim "$MNT"

umount "$MNT"
rmdir "$MNT"
kpartx -d "$LOOP"
losetup --detach "$LOOP"

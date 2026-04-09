#!/usr/bin/env bash

# Kiwi runs this hook chrooted in the build root after create_initrd and
# before the filesystem is synced to the raw disk. All bind mounts from
# the prepare phase are already gone, so anything we rm here actually
# comes out of the final image.
#
# grub2-mkconfig and the rest of the grub2 build tools can NOT be
# touched here — kiwi re-invokes grub2-mkconfig on the mounted disk
# after this hook. That cleanup happens in Makefile.docker instead,
# after kiwi has finished with the raw disk.

set -o errexit

# Dracut is the initramfs generator. Kiwi needed it up to the create_initrd
# step right before this hook runs; we don't need it at runtime.
rpm -e --nodeps dracut
rm -rf /usr/lib/dracut /etc/dracut.conf.d

# Kernel debug artifacts — only useful for crash analysis. The live kernel
# at /boot/Image (a symlink into this directory) is untouched.
rm -f /usr/lib/modules/*/vmlinux.xz
rm -f /usr/lib/modules/*/System.map

# Leftover build-time state that survived into image-root.
rm -rf /var/cache/zypp/* /var/cache/kiwi/* /var/cache/zypper/*
rm -rf /var/log/*
rm -rf /tmp/* /var/tmp/*
rm -f  /var/lib/rpm/__db.*
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*

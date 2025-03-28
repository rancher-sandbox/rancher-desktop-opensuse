#!/usr/bin/bash

set -o errexit -o nounset -o xtrace

# If we're using hybrid cgroups (v1 + v2), bind mount things so we get v2 only.
# This is required by buildkit.  Note that newer versions of WSL are already
# cgroups v2 any, so we need the detection.

if [[ ! -f /sys/fs/cgroup/cgroup.subtree_control ]]; then
    mount --bind /sys/fs/cgroup/unified /sys/fs/cgroup
fi

if ! mountpoint --quiet /sys/fs/bpf; then
    mount bpffs -t bpf /sys/fs/bpf
    mount --make-shared /sys/fs/bpf
fi

if ! mountpoint --quiet /proc/sys/fs/binfmt_misc; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
    mount --make-shared /proc/sys/fs/binfmt_misc
fi

exec /usr/bin/sleep inf

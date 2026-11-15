# syntax=docker/dockerfile:1-labs

FROM registry.opensuse.org/opensuse/bci/kiwi:10 AS builder
ARG type=qcow2.xz
ARG xz=-9
# The BCI kiwi image ships /etc/kiwi.yml with mapper and runtime_checks
# settings required for building inside Docker. Append xz -0 so kiwi
# does not waste time on compression we discard and recompress in
# Makefile.docker. Using --config would replace the existing file and
# lose the mapper setting, breaking loop devices.
RUN --mount=type=cache,target=/var/cache/zypp \
    zypper --non-interactive install parted && \
    echo -e '\nxz:\n  - options: '\''-0'\''' >> /etc/kiwi.yml
WORKDIR /build
COPY . /description
ENV ZYPP_PCK_PRELOAD=1 ZYPP_CURL2=1
# libzypp installs any package whose `Supplements: modalias(...)` matches
# a modalias of the machine running zypper. It reads those modaliases
# from /sys, and inside kiwi's chroot that is still the build host's
# /sys. So on a build host with an Intel CPU, zypper adds Intel
# microcode to the image, but a VM guest cannot use microcode. Point
# libzypp at /dev/null instead. That path is not a directory, in the
# container or in the chroot, so libzypp does not find any modaliases
# and the image does not depend on the build host's hardware.
ENV ZYPP_MODALIAS_SYSFS=/dev/null
RUN --security=insecure \
    --mount=type=cache,target=/var/cache/zypp \
    --mount=type=cache,target=/var/cache/kiwi \
    make -C /description -f Makefile.docker TYPE=${type} XZ_OPTIONS="${xz}"

FROM scratch
COPY --from=builder /build/distro.*.xz /

# syntax=docker/dockerfile:1-labs

FROM registry.opensuse.org/opensuse/bci/kiwi:10 AS builder
ARG type=qcow2
ARG NERDCTL_VERSION
ARG CRI_DOCKERD_VERSION
RUN --mount=type=cache,target=/var/cache/zypp \
    zypper --non-interactive install parted
WORKDIR /build
COPY . /description
ENV ZYPP_PCK_PRELOAD=1 ZYPP_CURL2=1
RUN --security=insecure \
    --mount=type=cache,target=/var/cache/zypp \
    --mount=type=cache,target=/var/cache/kiwi \
    make -C /description -f Makefile.docker TYPE=${type}

FROM scratch
COPY --from=builder /build/*.qcow2 /build/*.tar.xz /

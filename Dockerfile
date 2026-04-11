# syntax=docker/dockerfile:1-labs

FROM registry.opensuse.org/opensuse/bci/golang:stable AS gobuild
RUN git clone https://github.com/rancher-sandbox/rancher-desktop --depth=1 /app
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod \
    go build -ldflags '-s -w' -o /go/bin/network-setup ./src/go/networking/cmd/network
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod \
    go build -ldflags '-s -w' -o /go/bin/vm-switch ./src/go/networking/cmd/vm
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod \
    go build -ldflags '-s -w' -o /go/bin/wsl-proxy ./src/go/networking/cmd/proxy
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod \
    go build -ldflags '-s -w' -o /go/bin/rancher-desktop-guest-agent ./src/go/guestagent

COPY src /rd
WORKDIR /rd/rd-init
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg/mod \
    go build -ldflags '-s -w' -o /go/bin/rd-init .

FROM registry.opensuse.org/opensuse/bci/kiwi:10 AS builder
ARG type=qcow2.xz
ARG NERDCTL_VERSION
# The BCI kiwi image ships /etc/kiwi.yml with mapper and runtime_checks
# settings required for building inside Docker. Append xz -0 so kiwi
# does not waste time on compression we discard and recompress at
# xz -9 --extreme in Makefile.docker. Using --config would replace the
# existing file and lose the mapper setting, breaking loop devices.
RUN --mount=type=cache,target=/var/cache/zypp \
    zypper --non-interactive install parted && \
    echo -e '\nxz:\n  - options: '\''-0'\''' >> /etc/kiwi.yml
WORKDIR /build
COPY . /description
COPY --from=gobuild /go/bin/* /description/root/usr/local/bin/
ENV ZYPP_PCK_PRELOAD=1 ZYPP_CURL2=1
RUN --security=insecure \
    --mount=type=cache,target=/var/cache/zypp \
    --mount=type=cache,target=/var/cache/kiwi \
    make -C /description -f Makefile.docker TYPE=${type}

FROM scratch
COPY --from=builder /build/*.raw.xz /build/*.qcow2.xz /build/*.tar.xz /

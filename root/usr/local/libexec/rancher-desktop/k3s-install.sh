#!/usr/bin/env bash

# This script is executed by `k3s-install.service` to install k3s.
# KUBERNETES_VERSION should be set (via `params.service`).
set -o errexit -o pipefail -o nounset

info() {
    printf "\e[1;34m[INFO]\e[0m: %s\n" "$*" >&2
}

error() {
    printf "\e[1;31m[ERROR]\e[0m: %s\n" "$*" >&2
}

find_version() {
    if [[ ! -x /usr/local/bin/k3s ]]; then
        info "K3s is not installed"
        return
    fi
    # awk must read to EOF; `{print; exit}` closes the pipe while k3s
    # is still writing, and the SIGPIPE propagates via pipefail + errexit.
    /usr/local/bin/k3s --version 2>/dev/null | awk '/^k3s version/ { print $3 }'
}

install_k3s() {
    export INSTALL_K3S_VERSION=v${KUBERNETES_VERSION}+k3s1
    local INSTALLED_VERSION
    INSTALLED_VERSION="$(find_version)"
    if [[ "${INSTALLED_VERSION}" == "${INSTALL_K3S_VERSION}" ]]; then
        info "K3s ${INSTALL_K3S_VERSION} is already installed; skipping install"
        return
    fi

    # K3s needs to be (re-)installed; stop it if it is running.
    if systemctl is-active --quiet k3s.service; then
        info "Stopping k3s"
        systemctl stop k3s.service
    fi

    # Don't enable k3s at install time; add it as a want of
    # rancher-desktop.target instead.
    export INSTALL_K3S_SKIP_ENABLE=true

    (
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin
        curl --fail --silent --show-error --location --connect-timeout 10 --max-time 60 \
            https://get.k3s.io | sh -
    )
}

# Remove stale kubeconfig so k3s regenerates it on start.  We will always end up
# restarting it by the time we exit this script successfully.  (If we fail, then
# systemd will restart us before proceeding with starting `k3s.service` anyway.)
rm -f /etc/rancher/k3s/k3s.yaml

# Prevent k3s from being enabled with the old version if the install fails;
# we will re-enable it after a successful install.  This also prevents k3s
# from being started with the wrong container engine options.  This does not
# stop a running k3s, in case it is already at the correct version.
if systemctl is-enabled --quiet k3s.service; then
    info "Disabling k3s.service"
    systemctl disable k3s.service
fi

install_k3s

# Set the container engine options for k3s.
info "Configuring k3s for ${CONTAINER_ENGINE}"
case "${CONTAINER_ENGINE}" in
    containerd)
        echo > /etc/systemd/system/k3s.service.env \
            "K3S_CONTAINER_ENGINE_OPTIONS=--container-runtime-endpoint /run/k3s/containerd/containerd.sock"
        ;;
    moby)
        echo > /etc/systemd/system/k3s.service.env \
            "K3S_CONTAINER_ENGINE_OPTIONS=--docker"
        ;;
    *)
        error "Unknown container engine: ${CONTAINER_ENGINE}"
        exit 1
        ;;
esac

# Enable the k3s service (by marking it as a wanted by rancher-desktop.target)
# and start it.  It still waits for k3s-install.service (i.e. this process) to
# finish first.
info "Enabling k3s.service"
systemctl add-wants rancher-desktop.target k3s.service
# `systemctl add-wants` implicitly reloads the configuration.
# (Re-)start k3s so it picks up the new container engine options.  It won't
# actually start until this unit finishes.
systemctl restart --no-block k3s.service

#!/usr/bin/env bash

# Copyright © 2024 SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#======================================
# Include functions & variables
#--------------------------------------
test -f /.kconfig && . /.kconfig # spellcheck-ignore-line
test -f /.profile && . /.profile

set -o errexit

#======================================
# Import RPM keys
#--------------------------------------

# It's unclear why this is needed
rpmkeys --import /usr/lib/rpm/gnupg/keys/gpg-pubkey-*.asc # spellcheck-ignore-line

#======================================
# Load settings
#--------------------------------------
. build/versions.env

#======================================
# Install local files
#--------------------------------------

# Install nerdctl
tar xvf "build/nerdctl-${NERDCTL_VERSION}.tgz" -C /usr/local/ \
    bin/buildctl bin/buildkitd bin/nerdctl

# Move nerdctl to /usr/local/libexec and replace it with a wrapper,
# so we can later setup environment variables for nerdctl in there.
mkdir -p /usr/local/libexec/nerdctl
mv /usr/local/bin/nerdctl /usr/local/libexec/nerdctl/
cat <<EOF > /usr/local/bin/nerdctl
#!/bin/sh
exec /usr/local/libexec/nerdctl/nerdctl "\$@"
EOF
chmod 755 /usr/local/bin/nerdctl

# Install cri-dockerd
tar --extract --verbose --file "build/cri-dockerd-${CRI_DOCKERD_VERSION}.tgz" \
    --directory /usr/local/bin/ --strip-components=1 cri-dockerd/cri-dockerd
# Copy the LICENSE file for cri-dockerd
mkdir -p /usr/share/doc/cri-dockerd/
cp "build/cri-dockerd-${CRI_DOCKERD_VERSION}.LICENSE" /usr/share/doc/cri-dockerd/LICENSE

# Remove the build inputs
rm -rf /build/

#======================================
# Fixups
#--------------------------------------
baseStripLocales en_US C
baseStripTranslations en_US
for link in /usr/bin/busybox /bin/busybox $(cat /usr/share/busybox/busybox.links); do
    if [[ ! -e $link ]]; then
        ln --verbose /usr/bin/busybox-static $link
    fi
done
# tini-static has a different name
ln /usr/sbin/tini-static /usr/sbin/tini

# This file name is invalid on Windows, so we have to rename it as part of the
# build process to prevent issues checking the repository out.
mv /usr/local/lib/systemd/system/mnt-lima{-,\\x2d}cidata.mount

#======================================
# Fix permissions
#--------------------------------------
chown --recursive root:root /etc/sudoers.d
chmod 0750 /etc/sudoers.d
chmod 0644 /etc/sudoers.d/*
find /etc/systemd /usr/local/lib/systemd -type d -execdir chmod 0755 '{}' '+'
find /etc/systemd /usr/local/lib/systemd -type f -execdir chmod 0644 '{}' '+'
chmod 0755 /usr/local/bin/*
chmod 0755 /usr/local/libexec/rancher-desktop/setup-namespace.sh
chmod 0755 /usr/local/libexec/udhcpc/*.script

#======================================
# Enable services
#--------------------------------------
systemctl enable sshd

#======================================
# Linux/darwin-specific fixes
#--------------------------------------
if [[ ${kiwi_profiles:-} =~ lima ]]; then
    # Enable services
    systemctl enable buildkitd
    systemctl enable containerd
    systemctl enable docker
    systemctl enable systemd-networkd
    systemctl enable systemd-resolved

    systemctl enable lima-init.service
    systemctl enable rd-init.service
    # Disable network namespace related functionality (WSL only)
    rm -f /usr/local/lib/systemd/system/*/network-namespace.conf
    # Remove the docker config that is only used on Windows
    rm -f /root/.docker/config.json
fi

#======================================
# WSL-specific fixes
#--------------------------------------
if [[ ${kiwi_profiles:-} =~ wsl ]]; then
    # Enable network namespace
    systemctl enable network-setup
    systemctl enable rancher-desktop-guest-agent.service
    systemctl enable wsl-proxy.service
    # Do not manage /tmp; that is managed by WSL.
    mkdir -p /usr/local/lib/tmpfiles.d
    touch /usr/local/lib/tmpfiles.d/fs-tmp.conf
fi

#======================================
# Data distribution bootstrap
#--------------------------------------
if [[ ${kiwi_profiles:-} =~ wsl ]]; then
    mkdir -p /usr/share/rancher-desktop-data-distro/{bin,etc}
    ln /usr/bin/busybox-static /usr/share/rancher-desktop-data-distro/bin/busybox
    ln --symbolic busybox /usr/share/rancher-desktop-data-distro/bin/mount
    ln --symbolic busybox /usr/share/rancher-desktop-data-distro/bin/sh
    echo root:x:0:0:root:/root:/bin/sh > /usr/share/rancher-desktop-data-distro/etc/passwd
fi

#======================================
# Generate /etc/os-release; we do it this way to evaluate variables.
#--------------------------------------
. /etc/os-release
for field in $(busybox awk -F= '/=/{ print $1 }' /etc/os-release); do
  value="$(eval "echo \${${field}}")"
  if [ -n "${value}" ]; then
    echo "${field}=\"${value}\"" >> /tmp/os-release
  fi
done
mv /tmp/os-release /etc/os-release

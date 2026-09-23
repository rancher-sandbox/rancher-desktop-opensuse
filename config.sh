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

# containerd 1.7 installs shims for its deprecated v1 runtimes. Docker,
# nerdctl, buildkit and the CRI plugin all default to io.containerd.runc.v2.
# Omit -f so the build fails once containerd stops shipping the shims.
rm /usr/sbin/containerd-shim /usr/sbin/containerd-shim-runc-v1

#======================================
# Enable services
#--------------------------------------
# The Rancher Desktop units and their .wants symlinks now come from the
# distro-overlay manifest in rancher-desktop-daemon; only distro-provided
# services are enabled here.
systemctl enable sshd

#======================================
# Linux/darwin-specific fixes
#--------------------------------------
if [[ ${kiwi_profiles:-} =~ lima ]]; then
    systemctl enable systemd-networkd
    systemctl enable systemd-resolved
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

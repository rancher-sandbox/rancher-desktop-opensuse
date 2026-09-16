This directory contains scripts to build an OpenSUSE distribution for Rancher
Desktop.

## Usage

The distribution is built using `docker`:
```sh
make TYPE=raw.xz   # For macOS/VZ hosts (default)
make TYPE=qcow2.xz # For Linux/qemu hosts
make TYPE=tar.xz   # For WSL hosts
```

To cross-compile for a non-native architecture, set `GOARCH` to the target
architecture as used by the [go toolchain].  This requires your docker daemon to
be able to emulate that architecture.

[go toolchain]: https://go.dev/doc/install/source#environment

## Distro Overlay

Rancher Desktop adds nerdctl, buildkit and mkcert with the `distro-overlay`
tool from the [rancher-desktop-2] repository, so this image ships without them.
The tool appends them to the WSL tarball, or writes them into the free space
`config.kiwi` reserves in the raw image.

[rancher-desktop-2]: https://github.com/rancher-sandbox/rancher-desktop-2

## Release Process

Push a tag of the form `v*` (or `test-v*` for testing if testing in a fork is
not possible), and the [release workflow](.github/workflows/release.yaml) will
create a draft release with the artifacts.

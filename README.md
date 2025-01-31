This directory contains scripts to build an OpenSUSE distribution for Rancher
Desktop.

## Usage

The distribution is built using `docker`:
```sh
make TYPE=qcow2 # For Linux/darwin hosts
make TYPE=tar.xz # For WSL hosts
```

To cross-compile for a non-native architecture, set `GOARCH` to the target
architecture as used by the [go toolchain].  This requires your docker daemon to
be able to emulate that architecture.

[go toochain]: https://go.dev/doc/install/source#environment

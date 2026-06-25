#!/usr/bin/env bash

# This script is used by container-engine-select.service to start whichever
# container engine is selected.

set -o errexit -o pipefail -o nounset

containerd_units=(
    containerd.service
    buildkitd.service
    buildkitd.socket
)

moby_units=(
    docker.service
    docker.socket
)

printf 'Selecting container engine: "%s"\n' "${CONTAINER_ENGINE}"
# Both `systemctl disable` and `systemctl add-requires` implicitly reload the
# configuration, so we don't need to do it ourselves.  This can be confirmed by
# using `journalctl` to read the messages around when this occurs.
case "${CONTAINER_ENGINE}" in
    containerd)
        systemctl disable --now "${moby_units[@]}"
        systemctl add-requires container-engine.target "${containerd_units[@]}"
        ;;
    moby)
        systemctl disable --now "${containerd_units[@]}"
        systemctl add-requires container-engine.target "${moby_units[@]}"
        ;;
    *)
        printf 'Unknown container engine: "%s"\n' "${CONTAINER_ENGINE}" >&2
        exit 1
        ;;
esac

# Re-start container-engine.target so it picks up the newly-added requires.
systemctl start --no-block container-engine.target

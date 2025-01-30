# This is the main Makefile; it runs docker to build the actual image.

include root/build/versions.env

TYPE ?= qcow2
GOARCH ?= $(shell go env GOARCH)

# Default target is either `distro.qcow2` or `distro.tar.xz`
distro.${TYPE}:

INPUTS += root/build/nerdctl-$(NERDCTL_VERSION).tgz
root/build/nerdctl-$(NERDCTL_VERSION).tgz:
	wget -O "$@" \
		"https://github.com/$(NERDCTL_REPO)/releases/download/${NERDCTL_VERSION}/nerdctl-full-${NERDCTL_VERSION:v%=%}-linux-$(GOARCH).tar.gz"

INPUTS += root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).tgz
root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).tgz: root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE
	wget -O "$@" \
		"https://github.com/$(CRI_DOCKERD_REPO)/releases/download/${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION:v%=%}.$(GOARCH).tgz"
	touch --reference=$@ $<

INPUTS += root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE
root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE:
	wget -O "$@" \
		"https://raw.githubusercontent.com/$(CRI_DOCKERD_REPO)/$(CRI_DOCKERD_VERSION)/LICENSE"

distro.qcow2: config.kiwi config.sh ${INPUTS}
	if ! docker buildx inspect insecure-builder &>/dev/null; then \
		docker buildx create --name insecure-builder \
			--buildkitd-flags '--allow-insecure-entitlement security.insecure'; \
	fi
	docker buildx build --builder insecure-builder --allow security.insecure \
		$(if $(GITHUB_ACTION),--cache-from type=gha --cache-to type=gha) \
		--platform=linux/$(GOARCH) --output=. --build-arg=type=qcow2 .

distro.tar.xz: config.kiwi config.sh ${INPUTS}
	if ! docker buildx inspect insecure-builder &>/dev/null; then \
		docker buildx create --name insecure-builder \
			--buildkitd-flags '--allow-insecure-entitlement security.insecure'; \
	fi
	docker buildx build --builder insecure-builder --allow security.insecure \
		$(if $(GITHUB_ACTION),--cache-from type=gha --cache-to type=gha) \
		--platform=linux/$(GOARCH) --output=. --build-arg=type=tar.xz .

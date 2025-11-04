# This is the main Makefile; it runs docker to build the actual image.

include root/build/versions.env

GO ?= $(or $(shell which go.exe),$(shell which go))
GOARCH ?= $(shell $(GO) env GOARCH)
GOOS ?= $(shell $(GO) env GOOS)
TYPE ?= $(if $(filter windows,$(GOOS)),tar.xz,qcow2)

# Default target is either `distro.qcow2` or `distro.tar.xz`
distro.$(TYPE):

DOWNLOADS += root/build/nerdctl-$(NERDCTL_VERSION).tgz
root/build/nerdctl-$(NERDCTL_VERSION).tgz:
	wget -O "$@" \
		"https://github.com/$(NERDCTL_REPO)/releases/download/${NERDCTL_VERSION}/nerdctl-full-${NERDCTL_VERSION:v%=%}-linux-$(GOARCH).tar.gz"

DOWNLOADS += root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).tgz
root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).tgz: root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE
	wget -O "$@" \
		"https://github.com/$(CRI_DOCKERD_REPO)/releases/download/${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION:v%=%}.$(GOARCH).tgz"
	touch -r $@ $<

DOWNLOADS += root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE
root/build/cri-dockerd-$(CRI_DOCKERD_VERSION).LICENSE:
	wget -O "$@" \
		"https://raw.githubusercontent.com/$(CRI_DOCKERD_REPO)/$(CRI_DOCKERD_VERSION)/LICENSE"

IMAGE_FILES := \
	root/build/versions.env \
	$(filter-out .gitignore Makefile README.md root/build/% distro.%, $(shell find * -type f))

# To avoid $(if ...) from spliting on the commas in the command line, we need to
# provide this using a variable to add a layer of indirection.
BUILDX_CACHE_ARGS := \
	--cache-from=type=local,src=${RUNNER_TEMP}/cache \
	--cache-to=type=local,dest=${RUNNER_TEMP}/cache,compression=zstd,mode=max

distro.%: $(DOWNLOADS) $(IMAGE_FILES)
	if ! docker buildx inspect insecure-builder &>/dev/null; then \
		docker buildx create --name insecure-builder \
			--buildkitd-flags '--allow-insecure-entitlement security.insecure'; \
	fi
	docker buildx build --builder insecure-builder --allow security.insecure \
		 $(if $(RUNNER_TEMP),$(BUILDX_CACHE_ARGS)) \
		--platform=linux/$(GOARCH) --output=. --build-arg=type=$* .

clean:
	rm -f distro.tar.xz distro.qcow2 $(DOWNLOADS)

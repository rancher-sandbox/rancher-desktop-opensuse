# This is the main Makefile; it runs docker to build the actual image.

GO ?= $(or $(shell which go.exe),$(shell which go))
GOARCH ?= $(shell $(GO) env GOARCH)
GOOS ?= $(shell $(GO) env GOOS)
TYPE ?= $(if $(filter windows,$(GOOS)),tar.xz,raw.xz)

# Default target is either `distro.raw.xz` or `distro.tar.xz`
distro.$(TYPE):

# Compression of the final artifact, which dominates the build. Override it
# when the size does not matter, e.g. `make XZ_OPTIONS=-1` for a test build.
XZ_OPTIONS ?= -9

# Do not keep a partial image from a failed build.
.DELETE_ON_ERROR:

IMAGE_FILES := \
	$(filter-out .gitignore Makefile README.md distro.%, $(shell find * -type f))

# To avoid $(if ...) from spliting on the commas in the command line, we need to
# provide this using a variable to add a layer of indirection.
BUILDX_CACHE_ARGS := \
	--cache-from=type=local,src=${RUNNER_TEMP}/cache \
	--cache-to=type=local,dest=${RUNNER_TEMP}/cache,compression=zstd,mode=max

distro.%: $(IMAGE_FILES)
	if ! docker buildx inspect insecure-builder &>/dev/null; then \
		docker buildx create --name insecure-builder \
			--buildkitd-flags '--allow-insecure-entitlement security.insecure'; \
	fi
	docker buildx build --builder insecure-builder --allow security.insecure \
		 $(if $(RUNNER_TEMP),$(BUILDX_CACHE_ARGS)) \
		--platform=linux/$(GOARCH) --output=. --build-arg=type=$* \
		--build-arg=xz='$(XZ_OPTIONS)' .

clean:
	rm -f distro.raw.xz distro.qcow2.xz distro.tar.xz

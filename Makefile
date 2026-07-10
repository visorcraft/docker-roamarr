# Roamarr image build helpers.
#
# Builds use the docker image format so the Dockerfile HEALTHCHECK is preserved;
# podman's default OCI format silently drops it. `docker build` always honors
# HEALTHCHECK and needs no flag.

IMAGE ?= roamarr
TAG   ?= latest
# Optional Roamarr git ref override, e.g. `make build TAG=edge REF=master`.
REF   ?=

BUILD_ARGS := --format docker
ifneq ($(REF),)
BUILD_ARGS += --build-arg ROAMARR_REF=$(REF)
endif

.PHONY: build
build:
	podman build $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

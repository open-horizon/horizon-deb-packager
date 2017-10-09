SHELL := /bin/bash
ARCH := $(shell dpkg-architecture -q 'DEB_HOST_ARCH')

# docker build container
DOCKERB_CNAME := horizon-deb-packager
DOCKERB_INAME := $(DOCKERB_CNAME)-i
DOCKERB_TAG := $(shell cat VERSION)
DOCKERB_OPTS := --rm --no-cache
HORIZON_PKG_VERSION := $(cat $(horizon-deb-packager-dir/VERSION))

$(shell tools/flag.bash "$(DOCKERB_INAME):$(DOCKERB_TAG)" $(ARCH))
$(shell tools/flag.bash "$(DOCKERB_CNAME)" $(ARCH))

horizon-deb-packager-dir = $(shell dirname $(CURDIR))

all: artifacts

ifndef verbose
.SILENT:
endif

clean:
	@echo "Cleaning sources in build container, use *distclean* to remove containers and images created by this project"
	-if [[ "$$(docker ps | grep "$(DOCKERB_CNAME)")" != "" ]]; then \
		docker exec -it $(DOCKERB_CNAME) /bin/bash -c 'make clean'; \
	fi
#	@echo "Build container not running, skipping in-container clean execution"

# clean everything, including docker images
distclean: mostlyclean
	@echo "Cleaning containers and images"
	-if [[ "$$(docker ps | grep "$(DOCKERB_CNAME)")" != "" ]]; then \
		docker exec -it $(DOCKERB_CNAME) /bin/bash -c 'make distclean'; \
	fi
	-if [[ "$$(docker ps -a | grep "$(DOCKERB_CNAME)")" != "" ]]; then \
		docker rm -f "$(DOCKERB_CNAME)"; \
	fi
	-if [[ "$$(docker images -a | grep "$(DOCKERB_INAME)")" != "" ]]; then \
		docker rmi -f "$(DOCKERB_INAME):$(DOCKERB_TAG)"; \
	fi
	-rm -f *.flag
	# remove golang and node caches
	-rm -rf builder_homedir

# do not remove docker images
mostlyclean: clean
	@echo "Cleaning artifacts"
	-if [[ "$$(docker ps | grep "$(DOCKERB_CNAME)")" != "" ]]; then \
		docker exec -it $(DOCKERB_CNAME) /bin/bash -c 'make clean-src mostlyclean'; \
	fi
	-rm -f Dockerfile-*.bld

artifacts: $(DOCKERB_CNAME)-$(ARCH).flag
	@echo "Making artifacts using build container"
	docker exec -it $(DOCKERB_CNAME) /bin/bash -c 'make verbose=y git_repo_prefix=https://github.com/open-horizon skip-precheck=y TMPGOPATH=$$TMPGOPATH $$(make show-packages)'

# targets for build infrastructure
Dockerfile-$(ARCH).bld: Dockerfile.bld.tmpl
	tools/Dockerfile-render-bld.bash $(ARCH) Dockerfile.bld.tmpl Dockerfile-$(ARCH).bld

# TODO: this image flag turned out to be newer than the container flag and so forces a rebuild, why?
$(DOCKERB_INAME)_$(DOCKERB_TAG)-$(ARCH).flag: Dockerfile-$(ARCH).bld
	@echo "Building container image $(DOCKERB_INAME) ($(DOCKERB_INAME)_$(DOCKERB_TAG)-$(ARCH).flag) with context dir $(horizon-deb-packager-dir)"
	docker build $(DOCKERB_OPTS) -t $(DOCKERB_INAME) -f Dockerfile-$(ARCH).bld $(horizon-deb-packager-dir) && docker tag $(DOCKERB_INAME) $(DOCKERB_INAME):$(DOCKERB_TAG)

$(DOCKERB_CNAME)-$(ARCH).flag: $(DOCKERB_INAME)_$(DOCKERB_TAG)-$(ARCH).flag
	@echo "Running container $(DOCKERB_CNAME) $(DOCKERB_CNAME)-$(ARCH).flag"
	mkdir -p builder_homedir/go/.cache
	mkdir -p builder_homedir/.package_cache
	docker run -v $(horizon-deb-packager-dir):/horizon-deb-packager -e "HOME=/horizon-deb-packager/build_support/builder_homedir" -e "TMPGOPATH=/horizon-deb-packager/build_support/builder_homedir/go" -u $(shell id -u) -d --name $(DOCKERB_CNAME) -it $(DOCKERB_INAME):$(DOCKERB_TAG) /bin/sh

# to allay confusion, leave these around
.PRECIOUS: $(DOCKERB_CNAME)-$(ARCH).flag $(DOCKERB_INAME)_$(DOCKERB_TAG)-$(ARCH).flag $(DOCKERE_INAME)_$(DOCKERE_TAG)-$(ARCH).flag

.PHONY: artifacts

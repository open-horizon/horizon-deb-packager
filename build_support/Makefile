SHELL := /bin/bash
ARCH := $(shell dpkg --print-architecture)

# docker build container
DOCKERB_CNAME := horizon-deb-packager
DOCKERB_INAME := summit.hovitos.engineering/$(ARCH)/$(DOCKERB_CNAME)-i
DOCKERB_TAG := $(shell cat VERSION)
DOCKERB_OPTS := --rm --no-cache

# N.B. This has to be consistent with the decoding done by flag.bash
FLAGNAME = $(shell tools/dname_to_fname.bash "$(DOCKERB_INAME):$(DOCKERB_TAG)")

$(shell bash -c 'tools/flag.bash "$(DOCKERB_INAME)" "$(DOCKERB_TAG)"')

horizon-deb-packager-dir = $(shell dirname $(CURDIR))

all: artifacts

ifndef verbose
.SILENT:
endif

clean:
	@echo "Cleaning sources in build container, use *distclean* to remove containers and images created by this project"
	-docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'pwd && make clean'

# clean everything, including docker images
distclean: mostlyclean
	@echo "Cleaning containers and images"
	-rm -f *.flag
	-docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make distclean'
	-if [[ "$$(docker ps -a | grep "$(DOCKERB_CNAME)")" != "" ]]; then \
		docker rm -f "$(DOCKERB_CNAME)" > /dev/null; \
	fi
	-if [[ "$$(docker images -a | grep "$(DOCKERB_INAME)")" != "" ]]; then \
		docker rmi "$(DOCKERB_INAME):$(DOCKERB_TAG)" "$(DOCKERB_INAME):latest" > /dev/null; \
	fi

# do not remove docker images
mostlyclean: clean
	@echo "Cleaning artifacts"
	-rm -f Dockerfile-*.bld
	-docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make clean-src mostlyclean'; \

artifacts: $(FLAGNAME)
	@echo "Making artifacts using build container"
	docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make verbose=y git_repo_prefix=https://github.com/open-horizon skip-precheck=y mostlyclean packages'; \

# targets for build infrastructure
Dockerfile-$(ARCH).bld: Dockerfile.bld.tmpl
	tools/Dockerfile-render-bld.bash $(ARCH) Dockerfile.bld.tmpl Dockerfile-$(ARCH).bld

$(FLAGNAME): Dockerfile-$(ARCH).bld
	@echo "Building container image $(DOCKERB_INAME) with context dir $(horizon-deb-packager-dir)"
	docker build $(DOCKERB_OPTS) -t $(DOCKERB_INAME) -f Dockerfile-$(ARCH).bld $(horizon-deb-packager-dir) && docker tag $(DOCKERB_INAME) $(DOCKERB_INAME):$(DOCKERB_TAG)

# to allay confusion, leave these around
.PRECIOUS: $(FLAGNAME)

.PHONY: artifacts

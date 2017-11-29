SHELL := /bin/bash
buildarch := $(shell dpkg --print-architecture)

# the architecture of the eventual executable
arch ?= $(buildarch)

# TODO: replace this with discovery of all architectures by reading the metadata in the pkgsrc folder
architectures = amd64 arm64 armhf ppc64el

# docker build container
DOCKERB_CNAME := horizon-deb-packager
DOCKERB_INAME := summit.hovitos.engineering/$(buildarch)/$(DOCKERB_CNAME)-i
DOCKERB_TAG := $(shell cat VERSION)
DOCKERB_OPTS := --rm --no-cache

build_vars = git_repo_prefix=https://github.com/open-horizon skip-precheck=y

# N.B. This has to be consistent with the decoding done by flag.bash
FLAGNAME = $(shell tools/dname_to_fname.bash "$(DOCKERB_INAME):$(DOCKERB_TAG)")

$(shell bash -c 'tools/flag.bash "$(DOCKERB_INAME)" "$(DOCKERB_TAG)"')

horizon-deb-packager-dir = $(shell dirname $(CURDIR))

all: clean-build-all

ifndef verbose
.SILENT:
endif

clean:
	@echo "Cleaning sources in build container, use *distclean* to remove containers and images created by this project"
	-docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'pwd && make clean'

# clean everything, including docker images
distclean: mostlyclean
	@echo "Cleaning containers and images"
	-rm -f Dockerfile-*.bld
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
	-docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make clean-src mostlyclean'

src-artifacts: $(FLAGNAME)
	@echo "Making source artifacts using build container"
	docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make $(build_vars) mostlyclean src-packages'

artifacts: $(FLAGNAME)
	@echo "Making artifacts using build container"
	docker run --name "$(DOCKERB_CNAME)" --rm -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash -c 'make $(build_vars) arch=$(arch) mostlyclean packages'

clean-build-all: $(FLAGNAME)
# src-artifacts
	@echo "Making all artifacts for all architectures using build container"
	# important that we don't clean between builds of different architectures b/c they rely on the same source package or indexing will fail
	docker run --name "$(DOCKERB_CNAME)-all" -d -v $(horizon-deb-packager-dir):/horizon-deb-packager -u $(shell id -u) -it "$(DOCKERB_INAME):$(DOCKERB_TAG)" /bin/bash; \
	docker exec -it "$(DOCKERB_CNAME)-all" /bin/bash -c "make $(build_vars) src-packages"; \
	for ix_arch in $(architectures); do \
		echo "*** Building all packages for architecture $$ix_arch"; \
		SECONDS=0; \
		docker exec -it "$(DOCKERB_CNAME)-all" /bin/bash -c "make $(build_vars) arch=$$ix_arch packages"; \
		echo "*** Architecture $$ix_arch builds complete. Total build time: $$SECONDS s." ; \
	done
	-docker rm -f $(DOCKERB_CNAME)-all

# targets for build infrastructure
Dockerfile-$(buildarch).bld: Dockerfile.bld.tmpl
	tools/Dockerfile-render-bld.bash $(buildarch) Dockerfile.bld.tmpl Dockerfile-$(buildarch).bld

$(FLAGNAME): Dockerfile-$(buildarch).bld
	@echo "Building container image $(DOCKERB_INAME) with context dir $(horizon-deb-packager-dir)"
	docker build $(DOCKERB_OPTS) -t $(DOCKERB_INAME) -f Dockerfile-$(buildarch).bld $(horizon-deb-packager-dir) && docker tag $(DOCKERB_INAME) $(DOCKERB_INAME):$(DOCKERB_TAG)

show-flag:
	@echo "$(FLAGNAME)"

# to allay confusion, leave these around
.PRECIOUS: $(FLAGNAME)

.PHONY: artifacts clean distclean mostlyclean show-flag

SHELL := /bin/bash
subproject_names := anax
subprojects = $(addprefix bld/,$(subproject_names))

arch ?= $(shell tools/arch-tag)
dist ?= *

# The packager will build from a git branch or from master. In order to build a subproject branch, the
# deb packager project has to have the same branch name and this makefile is from that branch. That is,
# The builder must switch the deb pakcager project to the branch with the same name as the branch of the
# subprojects that need to be built and packaged.
branch_name ?= $(shell tools/branch-name)
version := $(shell cat VERSION)
version_tail = $(addprefix $(shell tools/branch-name "~")~ppa~,$(1))

#### Here too??
aug_version = $(addsuffix $(call version_tail,$(2)),$(1)$(version))

dist_dir = $(addprefix dist/horizon,$(addsuffix _$(arch),$(call aug_version,-,$(1))))
file_version = $(call aug_version,_,$(1))

git_repo_prefix ?= ssh://git@github.com/open-horizon

# only returns names of distributions that are valid for this architecture
distribution_names = $(shell find pkgsrc/deb/meta/dist/*$(dist)* -maxdepth 0 -exec bash -c 'for d; do if grep -q "$(arch)" "$${d}/arch"; then echo $$(basename $$d);  fi; done ' _ {} +)
all_distributions = $(shell find pkgsrc/deb/meta/dist/*$(dist)* -maxdepth 0 -exec bash -c 'for d; do echo $$(basename $$d); done' _ {} +)
release_only = $(lastword $(subst ., ,$1))
suite_prefix = $(addprefix $(release_only),$(shell tools/branch-name "-"))

file_stub = $(foreach dname,$(distribution_names),dist/$(1)$(call file_version,$(dname)))
noarch_file_stub = $(foreach dname,$(all_distributions),dist/$(1)$(call file_version,$(dname)))

meta = $(addprefix meta-,$(distribution_names))

src-packages = $(addsuffix .dsc,$(call noarch_file_stub,horizon))

config_deb_packages = $(foreach nameprefix, bluehorizon, $(addsuffix _all.deb, $(call noarch_file_stub,$(nameprefix))))

bin_stub = $(addsuffix _$(arch).deb,$(call file_stub,$1))
horizon_deb_packages = $(call bin_stub,horizon)
cli_deb_packages = $(call bin_stub,horizon-cli)

packages = $(horizon_deb_packages) $(config_deb_packages) $(cli_deb_packages)

debian_shared = $(shell find ./pkgsrc/deb/shared/debian -type f | sed 's,^./pkgsrc/deb/shared/debian/,,g' | xargs)

docker_tag_prefix := horizon

all: meta

ifndef verbose
.SILENT:
endif

bld:
	mkdir -p bld

bld/%/.git/logs/HEAD: | bld
	git clone $(git_repo_prefix)/$*.git "$(CURDIR)/bld/$*"
	cd $(CURDIR)/bld/$* && \
	if [ "$(branch_name)" != "" ]; then git checkout $(branch_name); else \
	  if [[ "$$(git tag -l $(docker_tag_prefix)/$(version)$(branch_name))" != "" ]]; then \
	  	git checkout -b "$(docker_tag_prefix)/$(version)$(branch_name)-b" $(docker_tag_prefix)/$(version)$(branch_name); \
	  fi; \
	fi

bld/%/.git-gen-changelog: bld/%/.git/logs/HEAD | bld
	bash tools/git-gen-changelog "$(CURDIR)/bld/$*" "$(CURDIR)/pkgsrc/deb/meta/changelog.tmpl" "$(docker_tag_prefix)/$(version)$(branch_name)"

bld/changelog.tmpl: pkgsrc/deb/meta/changelog.tmpl $(addsuffix /.git-gen-changelog,$(subprojects))
	mkdir -p bld
	if [[ "$$(cat pkgsrc/deb/meta/changelog.tmpl | head -n1 | grep $(version)$(branch_name))" != "" ]]; then \
		cp pkgsrc/deb/meta/changelog.tmpl bld/changelog.tmpl; \
	else \
		tools/render-debian-changelog "++DISTRIBUTIONS++" "$(version)$(branch_name)" "++VERSIONSUFFIX++" bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl $(shell find bld -iname ".git-gen-changelog"); \
	fi

$(call dist_dir,%)/debian:
	mkdir -p $(call dist_dir,$*)/debian

clean: clean-src mostlyclean
	@echo "Use distclean target to revert all configuration, in addition to build artifacts, and clean up horizon_$(version)$(branch_name) branch"
	-rm -f bld/changelog.tmpl
	-rm -Rf horizon* bluehorizon*
	-rm -Rf bld

clean-src:
	for src in $(subprojects); do \
		if [ -e $$src ]; then \
		  cd $$src && \
			git checkout . && \
			git reset --hard HEAD && \
			git clean -fdx; \
	  fi; \
	done

mostlyclean:
	-rm -Rf dist
	for src in $(subprojects); do \
		if [ -e $$src ]; then \
			cd $$src && $(MAKE) clean; \
	  fi; \
	done

distclean: clean
	@echo "distclean"
	# TODO: add other files to reset that might have changed?
	-@git reset VERSION
	if [[ "$(branch_name)" == "" ]]; then \
		-@git checkout master && git branch -D horizon_$(version)$(branch_name); \
	else \
		-@git checkout $(branch_name) && git branch -D horizon_$(version)$(branch_name); \
	fi

# both creates directory and fills it: this is not the best use of make but it is trivial work that can stay flexible
$(call dist_dir,%)/debian/fs-horizon: $(shell find pkgsrc/seed) | $(call dist_dir,%)/debian
	dir=$(call dist_dir,$*)/debian/fs-horizon && \
		mkdir -p $$dir && \
		./pkgsrc/mk-dir-trees $$dir && \
		cp -Ra ./pkgsrc/seed/horizon/fs/. $$dir && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl > $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json.example && \
		cp pkgsrc/mk-dir-trees $$dir/usr/horizon/sbin/

$(call dist_dir,%)/debian/fs-bluehorizon: $(call dist_dir,%)/debian/fs-horizon $(shell find pkgsrc/seed) | $(call dist_dir,%)/debian
	dir=$(call dist_dir,$*)/debian/fs-bluehorizon && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $$dir && \
		cp $(call dist_dir,$*)/debian/fs-horizon/etc/horizon/anax.json.example $$dir/etc/horizon/anax.json

# meta for every distribution, the target of horizon_$(version)-meta/$(distribution_names)
$(call dist_dir,%)/debian/changelog: bld/changelog.tmpl | $(call dist_dir,%)/debian
	sed "s,++DISTRIBUTIONS++,$(call suite_prefix,$*) $(addprefix $(call suite_prefix,$*)-,updates testing unstable),g" bld/changelog.tmpl > $(call dist_dir,$*)/debian/changelog
	sed -i.bak "s,++VERSIONSUFFIX++,$(call version_tail,$*),g" $(call dist_dir,$*)/debian/changelog && rm $(call dist_dir,$*)/debian/changelog.bak

# N.B. This target will copy all files from the source to the dest. as one target
$(addprefix $(call dist_dir,%)/debian/,$(debian_shared)): $(addprefix pkgsrc/deb/shared/debian/,$(debian_shared)) | $(call dist_dir,%)/debian
	cp -Ra pkgsrc/deb/shared/debian/. $(call dist_dir,$*)/debian/
	# next, copy specific package overwrites if they exist
	if [[ "$(ls pkgsrc/deb/meta/dist/$*/debian/*)" != "" ]]; then \
		cp -Ra pkgsrc/deb/meta/dist/$*/debian/* $(call dist_dir,$*)/debian/; \
	fi

dist/horizon$(call file_version,%).orig.tar.gz: $(call dist_dir,%)/debian/fs-horizon $(call dist_dir,%)/debian/fs-bluehorizon $(call dist_dir,%)/debian/changelog $(addprefix $(call dist_dir,%)/debian/,$(debian_shared))
	for src in $(subprojects); do \
        	if [ "$$(basename $$src)" == "anax" ]; then \
				sed -i.bak 's,local build,'${version}${branch_name}',' $${src}/version/version.go; \
        		rm -f $${src}/version/version.go.bak; \
        	fi; \
		bash -c "cd $${src} && make deps"; \
		rsync -a --exclude=".git*" $(PWD)/$$src $(call dist_dir,$*)/; \
		if [ -e $${src}-rules.env ]; then \
			cp $${src}-rules.env $(call dist_dir,$*)/$$(basename $$src)/rules.env; \
		fi; \
	done
	find dist/ -iname ".keep" -exec rm -f {} \;
	tar -c -C $(call dist_dir,$*) . | gzip -n > dist/horizon$(call file_version,$*).orig.tar.gz

$(src-packages):
dist/horizon$(call file_version,%).dsc: dist/horizon$(call file_version,%).orig.tar.gz
	@echo "Running src pkg build in $*'"
	-rm -Rf $(call dist_dir,$*)
	mkdir $(call dist_dir,$*) && tar zxf dist/horizon$(call file_version,$*).orig.tar.gz -C $(call dist_dir,$*)/
	cd $(call dist_dir,$*) && \
		debuild --preserve-envvar arch -a$(arch) -us -uc -S -sa -tc --lintian-opts --allow-root -X cruft,init.d,binaries

$(config_deb_packages):
dist/bluehorizon$(call file_version,%)_all.deb:
	@echo "Running arch all pkg build in $*; using dist/horizon$(call file_version,$*).dsc"
	-rm -Rf $(call dist_dir,$*)
	dpkg-source -x dist/horizon$(call file_version,$*).dsc $(call dist_dir,$*)
	cd $(call dist_dir,$*) && \
		debuild --preserve-envvar arch -a$(arch) -us -uc -A -sa -tc --lintian-opts --allow-root -X cruft,init.d,binaries

$(cli_deb_packages):
dist/horizon-cli$(call file_version,%)_$(arch).deb:
$(horizon_deb_packages):
dist/horizon$(call file_version,%)_$(arch).deb: dist/horizon$(call file_version,%).dsc
	@echo "Running bin pkg build in $*; using dist/horizon$(call file_version,$*).dsc' (building $(horizon_deb_packages))"
	-rm -Rf $(call dist_dir,$*)
	dpkg-source -x dist/horizon$(call file_version,$*).dsc $(call dist_dir,$*)
	cd $(call dist_dir,$*) && \
		debuild --preserve-envvar arch -a$(arch) -us -uc -B -sa -tc --lintian-opts --allow-root -X cruft,init.d,binaries

# This target is called by the travis yaml file after the deb packages are built but before they are deployed.
fss-containers:
	@echo "Building FSS containers for arch amd64 in ./bld/anax"
	cd bld/anax && \
		make arch=amd64 opsys=Linux all-nodeps && \
			make BRANCH_NAME=$(shell tools/branch-name "-") arch=amd64 fss-package

$(meta): meta-%: bld/changelog.tmpl dist/horizon$(call file_version,%).orig.tar.gz
ifndef skip-precheck
	tools/meta-precheck $(CURDIR) "$(docker_tag_prefix)/$(version)$(branch_name)" $(subprojects)
endif
	@echo "================="
	@echo "Metadata created"
	@echo "================="
	@echo "Please inspect $(call dist_dir,$*), the shared template file bld/changelog.tmpl, and VERSION. If accurate and if no other changes exist in the local copy, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing."

meta: $(meta)

src-packages: $(src-packages)

arch-packages: $(horizon_deb_packages) $(cli_deb_packages)

packages: $(packages)

noarch-packages: $(config_deb_packages)

show-distribution-names:
	@echo $(distribution_names)

show-subprojects:
	@echo $(subprojects)

show-src-packages:
	@echo $(src-packages)

show-arch-packages:
	@echo $(horizon_deb_packages) $(cli_deb_packages)

show-packages:
	@echo $(packages)

show-noarch-packages:
	@echo $(config_deb_packages)

publish-meta-bld/%:
	@echo "+ Visiting publish-meta subproject $*"
	tools/git-tag 0 "$(CURDIR)/bld/$*" "$(docker_tag_prefix)/$(version)$(branch_name)"

publish-meta: $(addprefix publish-meta-bld/,$(subproject_names))
	git checkout -b horizon_$(version)$(branch_name)
	cp bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl
	git add ./VERSION pkgsrc/deb/meta/changelog.tmpl
	git commit -m "updated package metadata to $(version)$(branch_name)"
	git push --set-upstream origin horizon_$(version)$(branch_name)

# make these "precious" so Make won't remove them
.PRECIOUS: dist/horizon$(call file_version,%).orig.tar.gz bld/%/.git/logs/HEAD $(call dist_dir,%)/debian $(addprefix $(call dist_dir,%)/debian/,$(debian_shared) changelog fs-horizon fs-bluehorizon)

.PHONY: clean clean-src $(meta) mostlyclean publish-meta publish-meta-bld/% show-distribution-names show-packages show-subprojects

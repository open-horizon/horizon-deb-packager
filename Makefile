SHELL := /bin/bash
subproject_names := anax anax-ui
subprojects = $(addprefix bld/,$(subproject_names))

arch ?= $(shell tools/arch-tag)

version := $(shell cat VERSION)
version_tail = $(addprefix ~ppa~,$(1))

aug_version = $(addsuffix $(call version_tail,$(2)),$(1)$(version))

dist_dir = $(addprefix dist/horizon,$(addsuffix _$(arch),$(call aug_version,-,$(1))))
file_version = $(call aug_version,_,$(1))

git_repo_prefix ?= ssh://git@github.com/open-horizon

# only returns names of distributions that are valid for this architecture
distribution_names = $(shell find pkgsrc/deb/meta/dist/* -maxdepth 0 -exec bash -c 'for d; do if grep -q "$(arch)" "$${d}/arch"; then echo $$(basename $$d);  fi; done ' _ {} +)
release_only = $(lastword $(subst ., ,$1))

file_stub = $(foreach dname,$(distribution_names),dist/$(1)$(call file_version,$(dname)))

meta = $(addprefix meta-,$(distribution_names))

src-packages = $(addsuffix .dsc,$(call file_stub,horizon))

bluehorizon_deb_packages = $(foreach nameprefix, bluehorizon bluehorizon-ui, $(addsuffix _all.deb,$(call file_stub,$(nameprefix))))
other_config_deb_packages = $(foreach nameprefix, horizon-wiotp, $(addsuffix _all.deb, $(call file_stub,$(nameprefix))))

bin_stub = $(addsuffix _$(arch).deb,$(call file_stub,$1))
horizon_deb_packages = $(call bin_stub,horizon)

packages = $(horizon_deb_packages) $(bluehorizon_deb_packages) $(other_config_deb_packages)

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
	if [ "$($(*)-branch)" != "" ]; then git checkout $($(*)-branch); else \
	  if [[ "$$(git tag -l $(docker_tag_prefix)/$(version))" != "" ]]; then \
	  	git checkout -b "$(docker_tag_prefix)/$(version)-b" $(docker_tag_prefix)/$(version); \
		fi; \
	fi

bld/%/.git-gen-changelog: bld/%/.git/logs/HEAD | bld
	bash tools/git-gen-changelog "$(CURDIR)/bld/$*" "$(CURDIR)/pkgsrc/deb/meta/changelog.tmpl" "$(docker_tag_prefix)/$(version)"

bld/changelog.tmpl: pkgsrc/deb/meta/changelog.tmpl $(addsuffix /.git-gen-changelog,$(subprojects))
	mkdir -p bld
	if [[ "$$(cat pkgsrc/deb/meta/changelog.tmpl | head -n1 | grep $(version))" != "" ]]; then \
		cp pkgsrc/deb/meta/changelog.tmpl bld/changelog.tmpl; \
	else \
		tools/render-debian-changelog "++DISTRIBUTIONS++" "$(version)" "++VERSIONSUFFIX++" bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl $(shell find bld -iname ".git-gen-changelog"); \
	fi

$(call dist_dir,%)/debian:
	mkdir -p $(call dist_dir,$*)/debian

clean: clean-src mostlyclean
	@echo "Use distclean target to revert all configuration, in addition to build artifacts, and clean up horizon_$(version) branch"
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
	-@git checkout master && git branch -D horizon_$(version)

# both creates directory and fills it: this is not the best use of make but it is trivial work that can stay flexible
$(call dist_dir,%)/debian/fs-horizon: $(shell find pkgsrc/seed) | $(call dist_dir,%)/debian
	dir=$(call dist_dir,$*)/debian/fs-horizon && \
		mkdir -p $$dir && \
		./pkgsrc/mk-dir-trees $$dir && \
		cp -Ra ./pkgsrc/seed/horizon/fs/. $$dir && \
		echo "SNAP_COMMON=/var/horizon" > $$dir/etc/default/horizon && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl >> $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json.example && \
		cp pkgsrc/mk-dir-trees $$dir/usr/horizon/sbin/

$(call dist_dir,%)/debian/fs-horizon-wiotp: $(shell find pkgsrc/seed) | $(call dist_dir,%)/debian
	dir=$(call dist_dir,$*)/debian/fs-horizon-wiotp && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/horizon-wiotp/fs/. $$dir && \
		envsubst < ./pkgsrc/seed/horizon-wiotp/dynamic/horizon.tmpl >> $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/horizon-wiotp/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json

$(call dist_dir,%)/debian/fs-bluehorizon: $(call dist_dir,%)/debian/fs-horizon $(shell find pkgsrc/seed) | $(call dist_dir,%)/debian
	dir=$(call dist_dir,$*)/debian/fs-bluehorizon && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $$dir && \
		cp $(call dist_dir,$*)/debian/fs-horizon/etc/horizon/anax.json.example $$dir/etc/horizon/anax.json

# meta for every distribution, the target of horizon_$(version)-meta/$(distribution_names)
$(call dist_dir,%)/debian/changelog: bld/changelog.tmpl | $(call dist_dir,%)/debian
	sed "s,++DISTRIBUTIONS++,$(call release_only,$*) $(addprefix $(call release_only,$*)-,updates testing unstable),g" bld/changelog.tmpl > $(call dist_dir,$*)/debian/changelog
	sed -i.bak "s,++VERSIONSUFFIX++,$(call version_tail,$*),g" $(call dist_dir,$*)/debian/changelog && rm $(call dist_dir,$*)/debian/changelog.bak

# N.B. This target will copy all files from the source to the dest. as one target
$(addprefix $(call dist_dir,%)/debian/,$(debian_shared)): $(addprefix pkgsrc/deb/shared/debian/,$(debian_shared)) | $(call dist_dir,%)/debian
	cp -Ra pkgsrc/deb/shared/debian/. $(call dist_dir,$*)/debian/
	# next, copy specific package overwrites if they exist
	if [[ "$(ls pkgsrc/deb/meta/dist/$*/debian/*)" != "" ]]; then \
		cp -Ra pkgsrc/deb/meta/dist/$*/debian/* $(call dist_dir,$*)/debian/; \
	fi

dist/horizon$(call file_version,%).orig.tar.gz: $(call dist_dir,%)/debian/fs-horizon-wiotp $(call dist_dir,%)/debian/fs-horizon $(call dist_dir,%)/debian/fs-bluehorizon $(call dist_dir,%)/debian/changelog $(addprefix $(call dist_dir,%)/debian/,$(debian_shared))
	for src in $(subprojects); do \
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

$(other_config_deb_packages):
dist/horizon-wiotp$(call file_version,%)_all.deb:
$(bluehorizon_deb_packages):
dist/bluehorizon$(call file_version,%)_all.deb:
dist/bluehorizon-ui$(call file_version,%)_all.deb: dist/horizon$(call file_version,%).dsc
	@echo "Running arch all pkg build in $*; using dist/horizon$(call file_version,$*).dsc'"
	-rm -Rf $(call dist_dir,$*)
	dpkg-source -x dist/horizon$(call file_version,$*).dsc $(call dist_dir,$*)
	cd $(call dist_dir,$*) && \
		debuild --preserve-envvar arch -a$(arch) -us -uc -A -sa -tc --lintian-opts --allow-root -X cruft,init.d,binaries

$(horizon_deb_packages):
dist/horizon$(call file_version,%)_$(arch).deb: dist/horizon$(call file_version,%).dsc
	@echo "Running bin pkg build in $*; using dist/horizon$(call file_version,$*).dsc' (building $(horizon_deb_packages))"
	-rm -Rf $(call dist_dir,$*)
	dpkg-source -x dist/horizon$(call file_version,$*).dsc $(call dist_dir,$*)
	cd $(call dist_dir,$*) && \
		debuild --preserve-envvar arch -a$(arch) -us -uc -B -sa -tc --lintian-opts --allow-root -X cruft,init.d,binaries

$(meta): meta-%: bld/changelog.tmpl dist/horizon$(call file_version,%).orig.tar.gz
ifndef skip-precheck
	tools/meta-precheck $(CURDIR) "$(docker_tag_prefix)/$(version)" $(subprojects)
endif
	@echo "================="
	@echo "Metadata created"
	@echo "================="
	@echo "Please inspect $(call dist_dir,$*), the shared template file bld/changelog.tmpl, and VERSION. If accurate and if no other changes exist in the local copy, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing."

meta: $(meta)

src-packages: $(src-packages)

arch-packages: $(horizon_deb_packages)

packages: $(packages)

noarch-packages: $(bluehorizon_deb_packages) $(other_config_deb_packages)

show-distribution-names:
	@echo $(distribution_names)

show-subprojects:
	@echo $(subprojects)

show-src-packages:
	@echo $(src-packages)

show-arch-packages:
	@echo $(horizon_deb_packages)

show-packages:
	@echo $(packages)

show-noarch-packages:
	@echo $(bluehorizon_deb_packages) $(other_config_deb_packages)

publish-meta-bld/%:
	@echo "+ Visiting publish-meta subproject $*"
	tools/git-tag 0 "$(CURDIR)/bld/$*" "$(docker_tag_prefix)/$(version)"

publish-meta: $(addprefix publish-meta-bld/,$(subproject_names))
	git checkout -b horizon_$(version)
	cp bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl
	git add ./VERSION pkgsrc/deb/meta/changelog.tmpl
	git commit -m "updated package metadata to $(version)"
	git push --set-upstream origin horizon_$(version)

# make these "precious" so Make won't remove them
.PRECIOUS: dist/horizon$(call file_version,%).orig.tar.gz bld/%/.git/logs/HEAD $(call dist_dir,%)/debian $(addprefix $(call dist_dir,%)/debian/,$(debian_shared) changelog fs-horizon fs-bluehorizon fs-horizon-wiotp)

.PHONY: clean clean-src $(meta) mostlyclean publish-meta publish-meta-bld/% show-distribution-names show-packages show-subprojects

SHELL := /bin/bash
arch-tag := $(shell tools/arch-tag)
subproject_names = anax anax-ui
subprojects = $(addprefix bld/,$(subproject_names))

version := $(shell cat VERSION)
version_tail = $(addprefix ~ppa~,$(1))
aug_version = $(addsuffix $(call version_tail,$(2)),$(1)$(version))
pkg_version = $(call aug_version,-,$(1))
file_version = $(call aug_version,_,$(1))

git_repo_prefix = ssh://git@github.com/open-horizon

# only returns names of distributions that are valid for this architecture
distribution_names = $(shell find pkgsrc/deb/meta/dist/* -maxdepth 0 -exec bash -c 'for d; do if grep -q "$(arch-tag)" "$${d}/arch"; then echo $$(basename $$d);  fi; done ' _ {} +)
release_only = $(lastword $(subst ., ,$1))

pkgstub = $(foreach dname,$(distribution_names),dist/$(1)$(call pkg_version,$(dname))_$(arch-tag).deb)

meta = $(addprefix meta-,$(distribution_names))

bluehorizon_deb_packages = $(foreach nameprefix, bluehorizon bluehorizon-ui, $(call pkgstub,$(nameprefix)))
horizon_deb_packages = $(call pkgstub,horizon)
packages = $(horizon_deb_packages) $(bluehorizon_deb_packages)

debian_shared = $(shell find ./pkgsrc/deb/shared/debian -type f | sed 's,^./pkgsrc/deb/shared/debian/,,g' | xargs)

docker_tag_prefix := horizon

all: meta

ifndef verbose
.SILENT:
endif

bld:
	mkdir -p bld

# TODO: consider making deps at this stage: that'd put all deps in the orig.tar.gz. This could be good for repeatable builds (we fetch from the internet all deps and wrap them in a source package), but it could be legally tenuous and there is still a chance of differences b/n .orig.tar.gzs between different arch's builds (b/c different machines run the builds and each fetches its own copy of those deps)
#-@[ ! -e "bld/$*" ] && git clone ssh://git@github.com/open-horizon/$*.git "$(CURDIR)/bld/$*" && cd $(CURDIR)/bld/$* && $(MAKE) deps
# TODO: could add capability to build from specified branch instead of master (right now this is only supported by doing some of the build steps, monkeying with the local copy and then running the rest of the steps.

bld/%/.git/logs/HEAD: | bld
	git clone $(git_repo_prefix)/$*.git "$(CURDIR)/bld/$*"
	cd $(CURDIR)/bld/$* && \
	if [ "$($(*)-branch)" != "" ]; then git checkout $($(*)-branch); else \
	  if [[ "$$(git tag -l $(docker_tag_prefix)/$(version))" != "" ]]; then \
	  	git checkout -b "$(docker_tag_prefix)/$(version)-b" $(docker_tag_prefix)/$(version); \
		fi; \
	fi

bld/%/.git-gen-changelog: bld/%/.git/logs/HEAD | bld
	bash -x tools/git-gen-changelog "$(CURDIR)/bld/$*" "$(CURDIR)/pkgsrc/deb/meta/changelog.tmpl" "$(docker_tag_prefix)/$(version)"

bld/changelog.tmpl: pkgsrc/deb/meta/changelog.tmpl $(addsuffix /.git-gen-changelog,$(subprojects))
	mkdir -p bld
	if [[ "$$(cat pkgsrc/deb/meta/changelog.tmpl | head -n1 | grep $(version))" != "" ]]; then \
		cp pkgsrc/deb/meta/changelog.tmpl bld/changelog.tmpl; \
	else \
		tools/render-debian-changelog "++DISTRIBUTIONS++" "$(version)" "++VERSIONSUFFIX++" bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl $(shell find bld -iname ".git-gen-changelog"); \
	fi

dist/horizon$(call pkg_version,%)/debian:
	mkdir -p dist/horizon$(call pkg_version,$*)/debian

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
dist/horizon$(call pkg_version,%)/debian/fs-horizon: $(shell find pkgsrc/seed) | dist/horizon$(call pkg_version,%)/debian
	dir=dist/horizon$(call pkg_version,$*)/debian/fs-horizon && \
		mkdir -p $$dir && \
		./pkgsrc/mk-dir-trees $$dir && \
		cp -Ra ./pkgsrc/seed/horizon/fs/. $$dir && \
		echo "SNAP_COMMON=/var/horizon" > $$dir/etc/default/horizon && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl >> $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json.example && \
		cp pkgsrc/mk-dir-trees $$dir/usr/horizon/sbin/

dist/horizon$(call pkg_version,%)/debian/fs-bluehorizon: dist/horizon$(call pkg_version,%)/debian/fs-horizon $(shell find pkgsrc/seed) | dist/horizon$(call pkg_version,%)/debian
	dir=dist/horizon$(call pkg_version,$*)/debian/fs-bluehorizon && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $$dir && \
		cp dist/horizon$(call pkg_version,$*)/debian/fs-horizon/etc/horizon/anax.json.example $$dir/etc/horizon/anax.json

# meta for every distribution, the target of horizon_$(version)-meta/$(distribution_names)
dist/horizon$(call pkg_version,%)/debian/changelog: bld/changelog.tmpl | dist/horizon$(call pkg_version,%)/debian
	sed "s,++DISTRIBUTIONS++,$(call release_only,$*) $(addprefix $(call release_only,$*)-,updates testing unstable),g" bld/changelog.tmpl > dist/horizon$(call pkg_version,$*)/debian/changelog
	sed -i.bak "s,++VERSIONSUFFIX++,$(call version_tail,$*),g" dist/horizon$(call pkg_version,$*)/debian/changelog && rm dist/horizon$(call pkg_version,$*)/debian/changelog.bak

# N.B. This target will copy all files from the source to the dest. as one target
$(addprefix dist/horizon$(call pkg_version,%)/debian/,$(debian_shared)): $(addprefix pkgsrc/deb/shared/debian/,$(debian_shared)) | dist/horizon$(call pkg_version,%)/debian
	cp -Ra pkgsrc/deb/shared/debian/. dist/horizon$(call pkg_version,$*)/debian/
	# next, copy specific package overwrites if they exist
	if [[ "$(ls pkgsrc/deb/meta/dist/$*/debian/*)" != "" ]]; then \
		cp -Rva pkgsrc/deb/meta/dist/$*/debian/* dist/horizon$(call pkg_version,$*)/debian/; \
	fi

dist/horizon$(call file_version,%).orig.tar.gz: dist/horizon$(call pkg_version,%)/debian/fs-horizon dist/horizon$(call pkg_version,%)/debian/fs-bluehorizon dist/horizon$(call pkg_version,%)/debian/changelog $(addprefix dist/horizon$(call pkg_version,%)/debian/,$(debian_shared))
	for src in $(subprojects); do \
		rsync -a --exclude=".git*" $(PWD)/$$src dist/horizon$(call pkg_version,$*)/; \
		if [ -e $${src}-rules.env ]; then \
			cp $${src}-rules.env dist/horizon$(call pkg_version,$*)/$$(basename $$src)/rules.env; \
		fi; \
	done
	tar --mtime="$(shell git log -1 --date=iso --format=%cd $(CURDIR)/VERSION)" --sort=name --user=root --group=root -c -C dist/horizon$(call pkg_version,$*) . | gzip -n > dist/horizon$(call file_version,$*).orig.tar.gz

# also builds the bluehorizon package
$(bluehorizon_deb_packages):
dist/bluehorizon$(call pkg_version,%)_$(arch-tag).deb:
dist/bluehorizon-ui$(call pkg_version,%)_$(arch-tag).deb:
$(horizon_deb_packages):
dist/horizon$(call pkg_version,%)_$(arch-tag).deb: dist/horizon$(call file_version,%).orig.tar.gz
	@echo "Running build in $* with TMPGOPATH '$(TMPGOPATH)'"
	cd dist/horizon$(call pkg_version,$*) && \
		debuild --preserve-envvar TMPGOPATH -a$(arch-tag) -us -uc --lintian-opts --allow-root
	find dist/* -exec touch -r $(CURDIR)/VERSION {} +

$(meta): meta-%: bld/changelog.tmpl dist/horizon$(call file_version,%).orig.tar.gz
ifndef skip-precheck
	tools/meta-precheck $(CURDIR) "$(docker_tag_prefix)/$(version)" $(subprojects)
endif
	@echo "================="
	@echo "Metadata created"
	@echo "================="
	@echo "Please inspect dist/horizon$(call pkg_version,$*), the shared template file bld/changelog.tmpl, and VERSION. If accurate and if no other changes exist in the local copy, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing."

meta: $(meta)

packages: $(packages)

publish-meta-bld/%:
	@echo "+ Visiting publish-meta subproject $*"
	tools/git-tag 0 "$(CURDIR)/bld/$*" "$(docker_tag_prefix)/$(version)"

publish-meta: $(addprefix publish-meta-bld/,$(subproject_names))
	git checkout -b horizon_$(version)
	cp bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl
	git add ./VERSION pkgsrc/deb/meta/changelog.tmpl
	git commit -m "updated package metadata to $(version)"
	git push --set-upstream origin horizon_$(version)

show-distribution-names:
	@echo $(distribution_names)

show-subprojects:
	@echo $(subprojects)

show-packages:
	@echo $(packages)

# make these "precious" so Make won't remove them
.PRECIOUS: dist/horizon$(call file_version,%).orig.tar.gz bld/%/.git/logs/HEAD dist/horizon$(call pkg_version,%)/debian $(addprefix dist/horizon$(call pkg_version,%)/debian/,$(debian_shared) changelog fs-horizon fs-bluehorizon)

.PHONY: clean clean-src $(meta) mostlyclean publish-meta publish-meta-bld/% show-distribution-names show-packages show-subprojects

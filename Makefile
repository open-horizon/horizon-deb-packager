SHELL := /bin/bash
ARCH := $(shell tools/arch-tag)
# N.B. This number has to match the latest addition to the changelog in pkgsrc/deb/debian/changelog
subproject_names = anax anax-ui
subproject = $(addprefix bld/,$(subproject_names))

##TODO: fix: this is all broken b/c the PACKAGEVERSION can't be statically specified
VERSION := $(shell cat VERSION)
DEB_REVISION := $(shell cat DEB_REVISION)

#TODO: just legacy
PACKAGEVERSION := $(VERSION)-$(PKG_REVISION)

distribution_names = $(shell find pkgsrc/deb/meta/dist/* -maxdepth 0 -exec basename {} \;)
pkgstub = $(foreach dname,$(distribution_names),dist/$(dname)/$1-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb)

meta = $(addprefix meta-,$(distribution_names))

bluehorizon_deb_packages = $(call pkgstub,bluehorizon)
horizon_deb_packages = $(call pkgstub,horizon)
package = $(bluehorizon_deb_packages) $(horizon_deb_packages) bluehorizon_$(VERSION)_$(ARCH).snap

debian_shared = $(shell find ./pkgsrc/deb/shared/debian -type f | sed 's,^./pkgsrc/deb/shared/debian/,,g' | xargs)

DOCKER_TAG_PREFIX := horizon

all: meta

ifndef VERBOSE
.SILENT:
endif

###
#unordered meta stuff
###

# we don't bother using snapcraft to do the build, just copy files around using its dump plugin
#bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap: seed-snap-stage horizon_$(PACKAGEVERSION)_$(ARCH).deb bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb $(wildcard pkgsrc/**/*)
	# copy snap stuff
# 	cp -Ra ./pkgsrc/snap/. horizon_$(VERSION)/snap
#
# 	sed -i "" "s,version:,version: $(PACKAGEVERSION),g" horizon_$(VERSION)/snap/snapcraft.yaml
# 	cd horizon_$(VERSION)/anax && \
# 		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon
# 	cd horizon_$(VERSION)/anax-ui && \
# 		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon
# 	cd horizon_$(VERSION)/snap && \
# 		snapcraft snap -o $(CURDIR)/bluehorizon_$(df
# 	ACKAGEVERSION)_$(ARCH).snap

clean: clean-src clean-snap mostlyclean
	@echo "Use distclean target to revert all configuration, in addition to build artifacts, and clean up horizon_$(VERSION) branch"
	-rm bld/changelog.tmpl
	-rm -Rf horizon* bluehorizon*
	-rm -Rf bld

clean-src:
	for src in $(subproject); do \
		if [ -e $$src ]; then \
		  cd $$src && \
			git checkout . && \
			git reset --hard HEAD && \
			git clean -fdx; \
	  fi; \
	done

mostlyclean:
	-rm -Rf dist
	for src in $(subproject); do \
		if [ -e $$src ]; then \
			cd $$src && $(MAKE) clean; \
	  fi; \
	done

clean-snap:
	@echo "clean-snap"
	-rm -Rf horizon_$(VERSION)/snap/{parts,prime,stage}

distclean: clean
	@echo "distclean"
	# TODO: add other files to reset that might have changed?
	-@git reset VERSION
	-@git checkout master && git branch -D horizon_$(VERSION)

bld/changelog.tmpl: pkgsrc/deb/meta/changelog.tmpl $(addsuffix /.git-gen-changelog,$(subproject))
	mkdir -p bld
	tools/render-debian-changelog "##DISTRIBUTIONS##" "##VERSION_RELEASE##" bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl $(shell find bld -iname ".git-gen-changelog")

dist/%/horizon_$(VERSION)/debian:
	mkdir -p dist/$*/horizon_$(VERSION)/debian

# both creates directory and fills it: this is not the best use of make but it is trivial work that can stay flexible
dist/%/horizon_$(VERSION)/debian/fs-horizon: $(shell find pkgsrc/seed) | dist/%/horizon_$(VERSION)/debian
	dir=dist/$*/horizon_$(VERSION)/debian/fs-horizon && \
		mkdir -p $$dir && \
		./pkgsrc/mk-dir-trees $$dir && \
		cp -Ra ./pkgsrc/seed/horizon/fs/. $$dir && \
		echo "SNAP_COMMON=/var/horizon" > $$dir/etc/default/horizon && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl >> $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json.example && \
		cp pkgsrc/mk-dir-trees $$dir/usr/horizon/sbin/

dist/%/horizon_$(VERSION)/debian/fs-bluehorizon: dist/%/horizon_$(VERSION)/debian/fs-horizon $(shell find pkgsrc/seed) | dist/%/horizon_$(VERSION)/debian
	dir=dist/$*/horizon_$(VERSION)/debian/fs-bluehorizon && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $$dir && \
		cp dist/$*/horizon_$(VERSION)/debian/fs-horizon/etc/horizon/anax.json.example $$dir/etc/horizon/anax.json

# meta for every distribution, the target of horizon_$(VERSION)-meta/$(distribution_names)
dist/%/horizon_$(VERSION)/debian/changelog: bld/changelog.tmpl | dist/%/horizon_$(VERSION)/debian
	sed "s,##DISTRIBUTIONS##,$* $(addprefix $*-,testing unstable),g" bld/changelog.tmpl > dist/$*/horizon_$(VERSION)/debian/changelog
	sed -i.bak "s,##VERSION_RELEASE##,$(VERSION)~$*-$(DEB_REVISION)~ppa,g" dist/$*/horizon_$(VERSION)/debian/changelog && rm dist/$*/horizon_$(VERSION)/debian/changelog.bak


# N.B. This target will copy all files from the source to the dest. as one target
$(addprefix dist/%/horizon_$(VERSION)/debian/,$(debian_shared)): $(addprefix pkgsrc/deb/shared/debian/,$(debian_shared)) | dist/%/horizon_$(VERSION)/debian
	cp -Ra pkgsrc/deb/shared/debian/. dist/$*/horizon_$(VERSION)/debian/
	# next, copy specific package overwrites
	cp -Ra pkgsrc/deb/meta/dist/$*/debian/. dist/$*/horizon_$(VERSION)/debian/

dist/%/horizon_$(VERSION)~%.orig.tar.gz: dist/%/horizon_$(VERSION)/debian/fs-horizon dist/%/horizon_$(VERSION)/debian/fs-bluehorizon dist/%/horizon_$(VERSION)/debian/changelog $(addprefix dist/%/horizon_$(VERSION)/debian/,$(debian_shared))
	for src in $(subproject); do \
		rsync -a --exclude=".git" $(PWD)/$$src dist/$*/horizon_$(VERSION)/; \
	done
	cd ./dist/$* && tar czf horizon_$(VERSION)~$*.orig.tar.gz *

# also builds the bluehorizon package
$(bluehorizon_deb_packages):
dist/%/bluehorizon-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb:
$(horizon_deb_packages):
dist/%/horizon-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb: dist/%/horizon_$(VERSION)~%.orig.tar.gz
	@echo "Running Debian build in $*"
	cd dist/$*/horizon_$(VERSION) && \
		debuild -us -uc --lintian-opts --allow-root

$(meta): meta-%: bld/changelog.tmpl dist/%/horizon_$(VERSION)~%.orig.tar.gz
	tools/meta-precheck $(CURDIR) "$(DOCKER_TAG_PREFIX)/$(VERSION)" $(subproject)
	@echo "================="
	@echo "Metadata created"
	@echo "================="
	@echo "Please inspect dist/$*/*, the shared template file bld/changelog.tmpl, and VERSION. If accurate and if no other changes exist in the local copy, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing."

meta: $(meta)

package: $(package)

publish-meta-bld/%:
	@echo "+ Visiting publish-meta subproject $*"
	tools/git-tag 0 "$(CURDIR)/bld/$*" "$(DOCKER_TAG_PREFIX)/$(VERSION)"

publish-meta: $(addprefix publish-meta-bld/,$(subproject_names))
	git checkout -b horizon_$(VERSION)
	cp bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl
	git add ./VERSION pkgsrc/deb/meta/changelog.tmpl
	git commit -m "updated package metadata to $(VERSION)"
	git push --set-upstream origin horizon_$(VERSION)

BLUEHORIZON-SNAP-OUTDIRBASE=dist/snap/fs
seed-snap-stage: seed-debian-stage clean-snap
	mkdir -p $(BLUEHORIZON-SNAP-OUTDIRBASE) && \
		./pkgsrc/mk-dir-trees $(BLUEHORIZON-SNAP-OUTDIRBASE)

	cp -Ra ./pkgsrc/seed/horizon/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon-snap-only/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)

	cp ./pkgsrc/seed/dynamic/horizon.tmpl $(BLUEHORIZON-SNAP-OUTDIRBASE)/etc/default/
	cp ./pkgsrc/seed/dynamic/anax.json.tmpl $(BLUEHORIZON-SNAP-OUTDIRBASE)/etc/horizon/
	cp ./pkgsrc/mk-dir-trees $(BLUEHORIZON-SNAP-OUTDIRBASE)/usr/horizon/sbin/

	find $(BLUEHORIZON-SNAP-OUTDIRBASE)/ -type d -empty -delete

show-package:
	@echo $(package)

show-subproject:
	@echo $(subproject)

show-distribution:
	@echo $(addprefix dist/,$(distribution_names))

show-distribution-names:
	@echo $(distribution_names)

bld:
	mkdir -p bld

# TODO: consider making deps at this stage: that'd put all deps in the orig.tar.gz. This could be good for repeatable builds (we fetch from the internet all deps and wrap them in a source package), but it could be legally tenuous and there is still a chance of differences b/n .orig.tar.gzs between different arch's builds (b/c different machines run the builds and each fetches its own copy of those deps)
	#-@[ ! -e "bld/$*" ] && git clone ssh://git@github.com/open-horizon/$*.git "$(CURDIR)/bld/$*" && cd $(CURDIR)/bld/$* && $(MAKE) deps
# TODO: could add capability to build from specified branch instead of master (right now this is only supported by doing some of the build steps, monkeying with the local copy and then running the rest of the steps.

bld/%/.git/logs/HEAD: | bld
	@echo "fetching $*"
	git clone ssh://git@github.com/open-horizon/$*.git "$(CURDIR)/bld/$*"

bld/%/.git-gen-changelog: bld/%/.git/logs/HEAD | bld
	tools/git-gen-changelog "$(CURDIR)/bld/$*" "$(CURDIR)/pkgsrc/deb/meta/changelog.tmpl" "$(DOCKER_TAG_PREFIX)/$(VERSION)"

# make these "precious" (including the basedir) so Make won't remove them under the assumption that they aren't needed after tarballs are created
.PRECIOUS: bld/%/.git/logs/HEAD dist/%/horizon_$(VERSION)/debian $(addprefix dist/%/horizon_$(VERSION)/debian/,$(debian_shared) changelog fs-horizon fs-bluehorizon)

.PHONY: clean clean-src clean-snap $(meta) publish-meta show-package show-subproject

SHELL := /bin/bash
ARCH := $(shell tools/arch-tag)
# N.B. This number has to match the latest addition to the changelog in pkgsrc/deb/debian/changelog
subproject_names = anax anax-ui
subproject = $(addprefix horizon_$(VERSION)_bld/,$(subproject_names))

##TODO: fix: this is all broken b/c the PACKAGEVERSION can't be statically specified
VERSION := $(shell cat VERSION)
DEB_REVISION := $(shell cat DEB_REVISION)

#TODO: just legacy
PACKAGEVERSION := $(VERSION)-$(PKG_REVISION)

distribution_names = $(shell find pkgsrc/deb/meta/dist/* -maxdepth 0 -exec basename {} \;)
pkgstub = $(foreach dname,$(distribution_names),horizon_$(VERSION)_dist/$(dname)/$1-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb)

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

bluehorizon_$(VERSION)_$(ARCH).snap:
	@echo "building snap"

clean: clean-src clean-snap
	@echo "Use distclean target to remove all build artifacts (across all versions) and clean up horizon_$(VERSION) branch"
	-rm horizon_$(VERSION)_bld/changelog.tmpl
	-rm -Rf horizon_$(VERSION)_dist

clean-src:
	@echo "clean-src"
	for src in $(subproject); do \
		if [ -e $$src ]; then \
		  cd $$src && \
			git checkout . && \
			$(MAKE) clean && \
			git reset --hard HEAD && \
			git clean -fdx; \
	  fi; \
	done

clean-snap:
	@echo "clean-snap"
	-rm -Rf horizon_$(VERSION)/snap/{parts,prime,stage}

distclean: clean
	@echo "distclean"
	-rm -Rf horizon* bluehorizon*
	-@git checkout master && git branch -D horizon_$(VERSION)

horizon_$(VERSION)_bld/changelog.tmpl: pkgsrc/deb/meta/changelog.tmpl $(addsuffix /.git-gen-changelog,$(subproject))
	mkdir -p horizon_$(VERSION)_bld
	tools/render-debian-changelog "##DISTRIBUTIONS##" "$(VERSION)-$(DEB_REVISION)" horizon_$(VERSION)_bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl $(shell find horizon_$(VERSION)_bld -iname ".git-gen-changelog")

horizon_$(VERSION)_dist/%/debian:
	mkdir -p horizon_$(VERSION)_dist/$*/debian

# both creates directory and fills it: this is not the best use of make but it is trivial work that can stay flexible
horizon_$(VERSION)_dist/%/debian/fs-horizon: $(shell find pkgsrc/seed) | horizon_$(VERSION)_dist/%/debian
	dir=horizon_$(VERSION)_dist/$*/debian/fs-horizon && \
		mkdir -p $$dir && \
		./pkgsrc/mk-dir-trees $$dir && \
		cp -Ra ./pkgsrc/seed/horizon/fs/. $$dir && \
		echo "SNAP_COMMON=/var/horizon" > $$dir/etc/default/horizon && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl >> $$dir/etc/default/horizon && \
		./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $$dir/etc/horizon/anax.json.example && \
		cp pkgsrc/mk-dir-trees $$dir/usr/horizon/sbin/

horizon_$(VERSION)_dist/%/debian/fs-bluehorizon: horizon_$(VERSION)_dist/%/debian/fs-horizon $(shell find pkgsrc/seed) | horizon_$(VERSION)_dist/%/debian
	@echo "making fs-bluehorizon"
	dir=horizon_$(VERSION)_dist/$*/debian/fs-bluehorizon && \
		mkdir -p $$dir && \
		cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $$dir && \
		cp horizon_$(VERSION)_dist/$*/debian/fs-horizon/etc/horizon/anax.json.example $$dir/etc/horizon/anax.json

# meta for every distribution, the target of horizon_$(VERSION)-meta/$(distribution_names)
horizon_$(VERSION)_dist/%/debian/changelog: horizon_$(VERSION)_bld/changelog.tmpl | horizon_$(VERSION)_dist/%/debian
	sed "s,##DISTRIBUTIONS##,$*,g" horizon_$(VERSION)_bld/changelog.tmpl > horizon_$(VERSION)_dist/$*/debian/changelog

# N.B. This target will copy all files from the source to the dest. as one target
$(addprefix horizon_$(VERSION)_dist/%/debian/,$(debian_shared)): $(addprefix pkgsrc/deb/shared/debian/,$(debian_shared)) | horizon_$(VERSION)_dist/%/debian
	@echo "Writing content to $*/debian/"
	cp -Ra pkgsrc/deb/shared/debian/. horizon_$(VERSION)_dist/$*/debian/
	# copy specific package overwrites next
	cp -Ra pkgsrc/deb/meta/dist/$*/debian/. horizon_$(VERSION)_dist/$*/debian/

horizon_$(VERSION)_dist/%/horizon_$(VERSION).orig.tar.gz: horizon_$(VERSION)_dist/%/debian/fs-horizon horizon_$(VERSION)_dist/%/debian/fs-bluehorizon horizon_$(VERSION)_dist/%/debian/changelog $(addprefix horizon_$(VERSION)_dist/%/debian/,$(debian_shared)) | $(subproject)
	@echo "Building tarball in $*"
	for src in $(subproject); do \
		ln -s $(PWD)/$$src horizon_$(VERSION)_dist/$*/ || :; \
	done
	tar czf horizon_$(VERSION)_dist/$*/horizon_$(VERSION).orig.tar.gz --dereference --exclude='.git*' --exclude='horizon_$(VERSION).orig.tar.gz' -C ./horizon_$(VERSION)_dist/$* .

# also builds the bluehorizon package
$(bluehorizon_deb_packages):
%/bluehorizon-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb:
$(horizon_deb_packages): horizon_$(VERSION)_dist/%/horizon-$(VERSION)-$(DEB_REVISION)_$(ARCH).deb: $(addprefix horizon_$(VERSION)_dist/,$(addsuffix /horizon_$(VERSION).orig.tar.gz,$(distribution_names)))
	@echo "Running Debian build in $*"
	cd $* && \
		debuild -us -uc --lintian-opts --allow-root

$(meta): meta-%: horizon_$(VERSION)_bld/changelog.tmpl horizon_$(VERSION)_dist/%/debian/changelog
	tools/meta-precheck $(CURDIR) "$(DOCKER_TAG_PREFIX)/$(VERSION)" $(subproject)
	@echo "================="
	@echo "Metadata created"
	@echo "================="
	@echo "Please inspect horizon_$(VERSION)_dist/$*, the shared template file horizon_$(VERSION)_bld/changelog.tmpl, and VERSION. If accurate and if no other changes exist in the local copy, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing."

meta: $(meta)

package: $(package)

publish-meta-horizon_$(VERSION)_bld/%:
	@echo "+ Visiting publish-meta subproject $*"
	tools/git-tag 0 "$(CURDIR)/horizon_$(VERSION)_bld/$*" "$(DOCKER_TAG_PREFIX)/$(VERSION)"

publish-meta: $(addprefix publish-meta-horizon_$(VERSION)_bld/,$(subproject_names))
	git checkout -b horizon_$(VERSION)
	cp horizon_$(VERSION)_bld/changelog.tmpl pkgsrc/deb/meta/changelog.tmpl
	git add ./VERSION pkgsrc/deb/meta/changelog.tmpl
	git commit -m "updated package metadata to $(VERSION)"
	git push --set-upstream origin horizon_$(VERSION)

BLUEHORIZON-SNAP-OUTDIRBASE=horizon_$(VERSION)_dist/snap/fs
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
	@echo $(addprefix horizon_$(VERSION)_dist/,$(distribution_names))

show-distribution-names:
	@echo $(distribution_names)

horizon_$(VERSION)_bld:
	mkdir -p horizon_$(VERSION)_bld

# TODO: could add capability to build from specified branch instead of master (right now this is only supported by doing some of the build steps, monkeying with the local copy and then running the rest of the steps.
$(subproject): horizon_$(VERSION)_bld/%: | horizon_$(VERSION)_bld
	-@[ ! -e "horizon_$(VERSION)_bld/$*" ] && git clone ssh://git@github.com/open-horizon/$*.git "$(CURDIR)/horizon_$(VERSION)_bld/$*"

horizon_$(VERSION)_bld/%/.git-gen-changelog: | horizon_$(VERSION)_bld/%
	tools/git-gen-changelog "$(CURDIR)/horizon_$(VERSION)_bld/$*" "$(CURDIR)/pkgsrc/deb/meta/changelog.tmpl" "$(DOCKER_TAG_PREFIX)/$(VERSION)"

# make these "precious" (including the basedir) so Make won't remove them under the assumption that they aren't needed after tarballs are created
.PRECIOUS: $(addprefix horizon_$(VERSION)_dist/%/debian/,/ $(debian_shared) changelog)

.PHONY: clean clean-src clean-snap $(meta) $(package) publish-meta show-package show-subproject $(subproject)

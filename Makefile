SHELL := /bin/bash
ARCH := $(shell tools/arch-tag)
VERSION := $(shell cat VERSION)
# N.B. This number has to match the latest addition to the changelog in pkgsrc/deb/debian/changelog
DEB_REVISION := $(shell cat DEB_REVISION)
PACKAGEVERSION := $(VERSION)-$(DEB_REVISION)
subprojects = horizon_$(VERSION)/anax \
							horizon_$(VERSION)/anax-ui
packages = horizon_$(PACKAGEVERSION)_$(ARCH).deb \
		bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb \
		bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap

TAG_PREFIX := horizon

all:

# we don't bother using snapcraft to do the build, just copy files around using its dump plugin
bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap: seed-snap-stage horizon_$(PACKAGEVERSION)_$(ARCH).deb bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb $(wildcard pkgsrc/**/*)
	# copy snap stuff
	cp -Ra ./pkgsrc/snap/. horizon_$(VERSION)/snap

	sed -i "s,version:,version: $(PACKAGEVERSION),g" horizon_$(VERSION)/snap/snapcraft.yaml
	cd horizon_$(VERSION)/anax && \
		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon
	cd horizon_$(VERSION)/anax-ui && \
		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon

	cd horizon_$(VERSION)/snap && \
		snapcraft snap -o $(CURDIR)/bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap

clean: clean-src clean-snap
	@echo "TODO: remove docker container, etc."

clean-src:
	-@[ -e "horizon_$(VERSION)"/anax-ui ] && cd horizon_$(VERSION)/anax-ui && $(MAKE) clean
	-@[ -e "horizon_$(VERSION)"/anax ] && cd horizon_$(VERSION)/anax && $(MAKE) clean
	-rm -Rf horizon* bluehorizon*

clean-snap:
	-rm -Rf horizon_$(VERSION)/snap/{parts,prime,stage}

# also builds the bluehorizon package
bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb:
horizon_$(PACKAGEVERSION)_$(ARCH).deb: horizon_$(VERSION).orig.tar.gz
	cd horizon_$(VERSION) && \
		debuild -us -uc --lintian-opts --allow-root

publish-meta-horizon_$(VERSION)/%:
	./tools/git-tag "$(PWD)/horizon_$(VERSION)/$*" "$(TAG_PREFIX)/$(VERSION)"

###################
# more specific to less specific
################

# N.B. This target depends on one that runs clean because the .orig tarball
# mustn't include the build artifacts. This could be improved to preserve
# built artifacts from anax, etc.
horizon_$(VERSION).orig.tar.gz: seed-debian-stage horizon_$(VERSION)/debian/changelog $(wildcard pkgsrc/**/*)
	tar czf horizon_$(VERSION).orig.tar.gz --dereference --exclude='.git*' ./horizon_$(VERSION)

# TODO: fix the dependencies, up-to-date is screwed on the horizon_$(VERSION)... targets and it's not phony like it should be
horizon_$(VERSION)/debian/changelog: horizon_$(VERSION)/debian $(subprojects) pkgsrc/debian/changelog
	tools/render-debian-changelog $(PACKAGEVERSION) horizon_$(VERSION)/debian/changelog pkgsrc/debian/changelog $(shell find horizon_$(VERSION)/ -iname ".git-gen-changelog")
	find horizon_$(VERSION)/ -iname ".git-gen-changelog" -exec rm {} \;

horizon_$(VERSION)/debian:
	mkdir -p horizon_$(VERSION)/debian

horizon_$(VERSION):
	mkdir -p horizon_$(VERSION)

meta: horizon_$(VERSION)/debian/changelog
	@echo "============"
	@echo "Metadata created."
	@echo "Please inspect horizon_$(VERSION)/debian/changelog and VERSION. If accurate, execute 'make publish-meta'. This will commit your local changes to the canonical upstream and tag dependent projects. The operation requires manual effort to undo so be sure you're ready before executing"
	@echo "============"

packages: $(packages)

publish-meta: publish-meta-$(SUBPROJECTS)
	@echo "not implemented; TODO: overwrite pkgsrc/debian/changelog, commit changelog and VERSION to this repo's canonical remote"

# paths here are expected by debian/rules file
HORIZON_STGFSBASE=horizon_$(VERSION)/debian/fs-horizon
BLUEHORIZON_STGFSBASE=horizon_$(VERSION)/debian/fs-bluehorizon
seed-debian-stage: horizon_$(VERSION) clean-src
	mkdir -p $(HORIZON_STGFSBASE) && \
		mkdir -p $(BLUEHORIZON_STGFSBASE) && \
			./pkgsrc/mk-dir-trees $(HORIZON_STGFSBASE)

	cp -Ra ./pkgsrc/seed/horizon/fs/. $(HORIZON_STGFSBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $(BLUEHORIZON_STGFSBASE)

	echo "SNAP_COMMON=/var/horizon" > $(HORIZON_STGFSBASE)/etc/default/horizon && \
		envsubst < ./pkgsrc/seed/dynamic/horizon.tmpl >> $(HORIZON_STGFSBASE)/etc/default/horizon

	./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $(HORIZON_STGFSBASE)/etc/horizon/anax.json.example
	cp ./pkgsrc/mk-dir-trees $(HORIZON_STGFSBASE)/usr/horizon/sbin/

	cp $(HORIZON_STGFSBASE)/etc/horizon/anax.json.example $(BLUEHORIZON_STGFSBASE)/etc/horizon/anax.json
	# copy deb stuff
	rsync -a --exclude="./pkgsrc/debian/changelog" ./pkgsrc/debian horizon_$(VERSION)/

BLUEHORIZON-SNAP-OUTDIRBASE=horizon_$(VERSION)/snap/fs
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

show-packages:
	@echo $(packages)

show-subprojects:
	@echo $(subprojects)

$(subprojects): horizon_$(VERSION)/%: horizon_$(VERSION)
	@echo "+ visiting target $*"
	./tools/git-clone ssh://git@github.com/open-horizon/$*.git "$(PWD)/horizon_$(VERSION)/$*" "$(TAG_PREFIX)/$(VERSION)" "$(PWD)/pkgsrc/debian/changelog"

.PHONY: clean clean-src clean-snap meta $(packages) publish publish-meta seed-snap-stage seed-debian-stage show-packages show-subprojects $(subprojects)

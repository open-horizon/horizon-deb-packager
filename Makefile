SHELL := /bin/bash
ARCH = $(shell tools/arch-tag)
VERSION = $(shell cat VERSION)
# N.B. This number has to match the latest addition to the changelog in pkgsrc/deb/debian/changelog
DEB_REVISION = $(shell cat DEB_REVISION)
PACKAGEVERSION = $(VERSION)-$(DEB_REVISION)

anax-branch = master
anax-ui-branch = master

all: horizon_$(PACKAGEVERSION)_$(ARCH).deb \
		bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb \
		bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap

# we don't bother using snapcraft to do the build, just copy files around using its dump plugin
bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap: seed-snap-stage horizon_$(PACKAGEVERSION)_$(ARCH).deb bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb $(wildcard pkgsrc/**/*)
	# copy snap stuff
	cp -Ra ./pkgsrc/snap/. horizon_$(VERSION)/snap

	sed -i "s,version:,version: $(PACKAGEVERSION),g" horizon_$(VERSION)/snap/snapcraft.yaml
	cd horizon_$(VERSION)/anax-src && \
		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon
	cd horizon_$(VERSION)/anax-ui-src && \
		$(MAKE) install DESTDIR=$(CURDIR)/horizon_$(VERSION)/snap/fs/usr/horizon

	cd horizon_$(VERSION)/snap && \
		snapcraft snap -o $(CURDIR)/bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap

clean: clean-src clean-snap
	@echo "TODO: remove docker container, etc."

clean-src:
	-cd horizon_$(VERSION)/anax-ui-src && $(MAKE) clean
	-cd horizon_$(VERSION)/anax-src && $(MAKE) clean
	-rm -Rf horizon* bluehorizon*

clean-snap:
	-rm -Rf horizon_$(VERSION)/snap/{parts,prime,stage}

# also builds the bluehorizon package
bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb:
horizon_$(PACKAGEVERSION)_$(ARCH).deb: horizon_$(VERSION).orig.tar.gz
	cd horizon_$(VERSION) && \
		echo "$(PACKAGEVERSION)" > ./debian/PACKAGEVERSION && \
		debuild -us -uc

horizon_$(VERSION):
	mkdir -p horizon_$(VERSION)

# N.B: this target will pull anax from the canonical repo w/ the tag $(VERSION)
# if it exists, HEAD if not. During publishing, this Makefile will push a tag
# to anax. That means that you can bump the VERSION number first, then build
# from head and the build will be repeatable later with the same VERSION value.
horizon_$(VERSION)/%-src: horizon_$(VERSION)
	git clone https://github.com/open-horizon/$*.git horizon_$(VERSION)/$*-src
ifneq ($($*-branch),"master")
	cd horizon_$(VERSION)/$*-src && git checkout $($*-branch)
else
	# ok for this one to fail, it merely means that we aren't building a previously-build, tagged version
	-cd horizon_$(VERSION)/$*-src && git checkout tags/$(VERSION)
endif

# N.B. This target runs clean because the .orig tarball mustn't include the
# build artifacts. This could be improved to preserve built artifacts from
# anax, etc.
horizon_$(VERSION).orig.tar.gz: seed-debian-stage horizon_$(VERSION)/anax-src horizon_$(VERSION)/anax-ui-src $(wildcard pkgsrc/**/*)
	# copy deb stuff
	cp -Ra ./pkgsrc/debian horizon_$(VERSION)
	-find ./horizon_$(VERSION) -iname "*.git*" -delete
	tar czf horizon_$(VERSION).orig.tar.gz --dereference ./horizon_$(VERSION)

pkgs:
	@echo horizon_$(PACKAGEVERSION)_$(ARCH).deb
	@echo bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb
	@echo bluehorizon_$(PACKAGEVERSION)_$(ARCH).snap

# paths here are expected by debian/rules file
HORIZON_STGFSBASE=horizon_$(VERSION)/debian/fs-horizon
BLUEHORIZON_STGFSBASE=horizon_$(VERSION)/debian/fs-bluehorizon
seed-debian-stage: horizon_$(VERSION) clean-src
	mkdir -p $(HORIZON_STGFSBASE) && \
		mkdir -p $(BLUEHORIZON_STGFSBASE) && \
			./pkgsrc/mk-dir-trees $(HORIZON_STGFSBASE)

	cp -Ra ./pkgsrc/seed/horizon/fs/. $(HORIZON_STGFSBASE)
	cp -Ra ./pkgsrc/seed/horizon-only/fs/. $(HORIZON_STGFSBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $(BLUEHORIZON_STGFSBASE)

	./pkgsrc/render-json-config ./pkgsrc/seed/dynamic/anax.json.tmpl $(HORIZON_STGFSBASE)/etc/horizon/anax.json.example
	cp $(HORIZON_STGFSBASE)/etc/horizon/anax.json.example $(BLUEHORIZON_STGFSBASE)/etc/horizon/anax.json

BLUEHORIZON-SNAP-OUTDIRBASE=horizon_$(VERSION)/snap/fs
seed-snap-stage: seed-debian-stage clean-snap
	mkdir -p $(BLUEHORIZON-SNAP-OUTDIRBASE) && \
		./pkgsrc/mk-dir-trees $(BLUEHORIZON-SNAP-OUTDIRBASE)

	cp -Ra ./pkgsrc/seed/horizon/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)
	cp -Ra ./pkgsrc/seed/bluehorizon-snap-only/fs/. $(BLUEHORIZON-SNAP-OUTDIRBASE)

	cp ./pkgsrc/mk-dir-trees $(BLUEHORIZON-SNAP-OUTDIRBASE)
	cp ./pkgsrc/seed/dynamic/anax.json.tmpl $(BLUEHORIZON-SNAP-OUTDIRBASE)/etc/horizon/

	find $(BLUEHORIZON-SNAP-OUTDIRBASE)/ -type d -empty -delete

.PHONY: clean clean-src clean-snap seed-snap-stage seed-debian-stage pkgs

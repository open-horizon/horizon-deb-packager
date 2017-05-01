SHELL := /bin/bash
ARCH = $(shell uname -m)
VERSION = $(shell cat VERSION)
# N.B. This number has to match the latest addition to the changelog in pkgsrc/deb/debian/changelog
DEB_REVISION = $(shell cat DEB_REVISION)
PACKAGEVERSION = $(VERSION)-$(DEB_REVISION)

anax-branch = master
anax-ui-branch = master

all: horizon_$(PACKAGEVERSION)_$(ARCH).deb \
		bluehorizon_$(PACKAGEVERSION)_$(ARCH).deb

clean: -clean-src
	@echo "TODO: remove docker container, etc."

-clean-src:
	-cd horizon_$(VERSION)/anax-ui-src && $(MAKE) clean
	-cd horizon_$(VERSION)/anax-src && $(MAKE) clean
	-rm -Rf horizon* bluehorizon*

%_$(PACKAGEVERSION)_$(ARCH).deb: %_$(VERSION).orig.tar.gz
	cd $*_$(VERSION) && \
		echo "$(PACKAGEVERSION)" > ./debian/PACKAGEVERSION && \
		debuild -us -uc

# N.B. This target runs clean because the .orig tarball mustn't include the
# build artifacts. This could be improved to preserve built artifacts from
# anax, etc.
horizon_$(VERSION).orig.tar.gz: -clean-src horizon_$(VERSION)/anax-src horizon_$(VERSION)/anax-ui-src $(wildcard pkgsrc/**/*)
	cp -Ra ./pkgsrc/deb/debian horizon_$(VERSION)/
	mkdir horizon_$(VERSION)/tmp && \
		cp -Ra ./pkgsrc/common horizon_$(VERSION)/tmp/
	  cp -Ra ./pkgsrc/deb/conf horizon_$(VERSION)/tmp/
	  cp -Ra ./pkgsrc/deb/service horizon_$(VERSION)/tmp/
	tar czf horizon_$(VERSION).orig.tar.gz --dereference ./horizon_$(VERSION)

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
	-find horizon_$(VERSION)/$*-src -name ".git*" -exec rm -Rf {} \;

horizon_$(VERSION):
	mkdir -p horizon_$(VERSION)

.PHONY: clean

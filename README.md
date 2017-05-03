# horizon-pkg

A project used to create and publish Debian packages and Ubuntu snaps of the Horizon platform. Current supported platforms include:

 * Raspbian armhf
 * Ubuntu 16.04 arm64, amd64, ppc64

## Use

### Installation from pkg.bluehorizon.network

`TODO`

### Installation from on-disk packages

#### Snap

    snap install --devmode --force-dangerous ./bluehorizon...snap

#### Debian packages

    dpkg -i horizon-<version>.deb bluehorizon-<version>.deb

### Post-installation tasks

You may wish to customize the configuration of Horizon before you start its services. Consult the appropriate section below for instructions on that topic.

#### Debian packages

To start Horizon services, execute:

    systemctl start horizon.service

To enable service startup at system boot, execute:

    systemctl enable horizon.service

### Configuration customization

#### Snap

#### Debian packages

The `horizon` and `bluehorizon` packages use configuration in `/etc/horizon`, `/etc/default/horizon`, and `/etc/systemd/system/horizon.service`. Edit the values as you'd like. Note that if you change the systemd unit file, you must execute `systemctl daemon-reload` for the changes to take effect.

## Development

### Preconditions

#### Accounts and keys

You need an account on the destination for build artifacts, pkgs.bluehorizon.network and a GPG key for signing packages.

#### Build system

A build box requires building, packaging, and signing software. Build a container appropriate for your architecture (some of this will be automated soon):

    docker build -t hzn-build -f Dockerfile-bld-armhf .
    docker build -t hzn-build -f Dockerfile-bld-amd64 .

### Operations

Start a build container with your GPG key and the project source mounted inside:

    docker run --rm --name hzn-build -v $HOME/.gnupg:/root/.gnupg:ro -v $PWD:/prj -it hzn-build:latest /bin/bash

#### Building artifacts

The build system is intended to build either new or existing versions of Horizon packages. To build new version of a package, update the `VERSION` or `DEB_REVISION` files' content and make an entry in the Debian changelog for that version with the command `dch -i`. After that, execute:

    make all

Optionally, you can specify a source branch for either or both of the source projects that make up Horizon packages:

    make anax-branch="pkg/deb" anax-ui-branch="pkg/deb" all

#### Publishing artifacts

    (TODO)

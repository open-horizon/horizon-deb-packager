# horizon-deb-packager

(formerly `horizon-pkg`)

## Introduction

A project used to create and publish Debian packages of the Horizon platform. Current supported architectures and distributions include:

 * Distributions: Ubuntu Xenial and Bionic (Arch: amd64, armhf, arm64 ppc64el); Raspbian Stretch (Arch: armhf)

Debian packages produced by this process are installed by a user where the user knows:
 * which operating system they need
 * which stream of code they want (where the name of the stream includes our branch name)

That information is specified in an apt sources.list file as follows, e.g.:
deb [arch=amd64] http://pkg.bluehorizon.network/linux/ubuntu xenial-testing main

where xenial-testing is the distribution suite and main is the component

This project also produces containers and pushes them into dockerhub.

When producing packages and containers for a source branch that is not master, the branch name appears in the suite name, e.g. xenial-la-testing for the la branch.

The process of building the packages and containers is quite complex, as outlined in the following steps:
1. The ./VERSION file is modified with a new version number.
2. make meta is called to produce the appropriate changelog for the new packages.
3. make meta-publish is called to commit the changes and trigger a Travis job that builds the packages and containers in the background.
4. The Travis job is defined by the .travis.yml file.
5. This job invokes the ./build_support/Makefile all-artifacts target
6. The build_support/Makefile creates and runs a special build container to create the deb packages and containers one at a time for each linux distribution that we support and for each architecture that we support.
7. If everything worked, the deb packages are uploaded by the ./tools/aptpoller and the containers are uploaded to dockerhub.

Related Projects:

 * `anax` (http://github.com/open-horizon/anax): The client control application in the Horizon system
 * `raspbian-image` (http://github.com/open-horizon/raspbian-image): The Raspbian image builder for Raspberry Pi 2 and 3 models dedicated to Horizon

## Manual use

### Publishing new versions using remote builders

Steps:

1. Check out this repository using the `ssh` clone method
2. Update the `VERSION` string in this repository's root directory. Use the following criteria:
    * Increment the micro version (*z* in x.y.z) if there are changes in the source repositores that are limited to bug fixes
    * Increment the minor version (*y* in x.y.z) if source changes only include new features or other non-breaking changes to the system
    * Increment the major version (*x* in x.y.z) if there are any source changes  that change external interfaces or configuration files such that old clients will fail to behave with the new version as they could with older versions and configuration *or* if the behavior of the system changes substantially such that existing users cannot expect the same behavior of the new version as they could from older versions
3. Execute `make meta[-distribution_name]`
4. Review the changes to the local repository as instructed by cli output
5. If satisfied with the proposed changes, execute `make publish-meta`

### Creating a local version

    cd build_support/ && make dist=ubuntu.xenial

This command will build all packages for all supported architectures for the supplied distribution.

## Running your own build agent

Docker build agent container creation command examples:

    cd build_support/ && make $(make show-flag)

**Note**: You must have appropriate SSH keys added to the agent to: 1) pull code from the repository, and 2) push built packages to the apt signing system.

Docker start command example:

    docker run --rm --name hzn-build --hostname=$(hostname) -v /root/.ssh-aptrepo-signer:/root/.ssh:ro -v /root/go/.cache:/root/go/.cache:rw -v /root/.package_cache:/root/.package_cache:rw -it summit.hovitos.engineering/amd64/horizon-deb-packager-i:latest /bin/bash -c '/prj/build_support/bin/watch-build 1 "/horizon-deb-packager" "http://pkg.bluehorizon.network/linux/##DIST##/dists/##RELEASE##-testing/main" "aptsigner:/incoming" "https://hooks.slack.com/services/..." [restrict_to_distro1,restrict_to_distro2]'

### Manual build with a build agent

In order to execute `make meta` inside a container, you need ssh credentials in-container and/or the ssh agent's authorization socket mounted into the build container. You can execute it this way:

    docker run --rm --name hzn-build-manual -v $PWD:/horizon-deb-packager -it hzn-build /bin/bash

Inside the container, change the `VERSION` and then execute the build steps (constraining the packages to `xenial` in the example below):

    make verbose=y git_repo_prefix=https://github.com/open-horizon skip-precheck=y $(make show-packages | xargs -n1 | grep xenial | xargs)

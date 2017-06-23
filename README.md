# horizon-pkg

A project used to create and publish Debian packages and Ubuntu snaps of the Horizon platform. Current supported platforms include:

 * Raspbian armhf
 * Ubuntu 16.04 arm64, amd64, ppc64

## Manual use

### Publishing new versions

Steps:

0. Check out this repository using the `ssh` clone method
0. Update the `VERSION` string in this repository's root directory. Use the following criteria:
  * Increment the micro version (*z* in x.y.z) if there are changes in the source repositores that are limited to bug fixes
  * Increment the minor version (*y* in x.y.z) if source changes only include new features or other non-breaking changes to the system
  * Increment the major version (*x* in x.y.z) if there are any source changes  that change external interfaces or configuration files such that old clients will fail to behave with the new version as they could with older versions and configuration *or* if the behavior of the system changes substantially such that existing users cannot expect the same behavior of the new version as they could from older versions
0. Execute `make meta[-distribution_name]`
0. Review the changes to the local repository as instructed by cli output
0. If satisfied with the proposed changes, execute `make publish-meta`

## Build agent

Docker build agent container creation command examples:

    docker build -t hzn-build -f Dockerfile-bld-armhf .
    docker build -t hzn-build -f Dockerfile-bld-amd64 .

**Note**: You must have appropriate SSH keys added to the agent to: 1) pull code from the repository, and 2) push built packages to the apt signing system.

Docker start command example:

    docker run --rm --name hzn-build -v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent -v $HOME/.ssh-github:/root/.ssh:ro -v $PWD:/prj -it hzn-build:latest /bin/bash -c '/prj/continuous_delivery/bin/watch-build http://pkg.bluehorizon.network/linux/ubuntu/dists/xenial-testing/main/binary-amd64/Packages.gz https://raw.githubusercontent.com/open-horizon/horizon-pkg/master/VERSION'

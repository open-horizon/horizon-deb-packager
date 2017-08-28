# horizon-pkg Apt Repository System

## aptsigner

Reprepro fork at https://github.com/michaeldye/reprepro.

Start command:

    docker run -d --name horizon-aptrepo -v /root/.gnupg/:/root/.gnupg:rw -v /var/tmp:/var/tmp:rw -v /vol/aptrepo-local:/var:rw -t aptrepo /bin/sh

TODO: describe keying system

### Common commands

See also http://www.red-bean.com/doc/reprepro/manual.html

#### Promote package

    docker exec -it horizon-aptrepo bash -c 'reprepro -b /var/repositories/ubuntu copy xenial-updates xenial-testing {blue,}horizon=2.0.17~ppa~ubuntu.xenial'
    Exporting indices...
    docker exec -it horizon-aptrepo bash -c 'reprepro -b /var/repositories/raspbian copy jessie-updates jessie-testing {blue,}horizon=2.0.17~ppa~raspbian.jessie'
    Exporting indices...

#### List packages in a suite

    docker exec -it horizon-aptrepo bash -c 'reprepro -b /var/repositories/ubuntu list xenial-updates'

## aptrepo

Start command:

    docker run --name horizon-reposerv -p 0.0.0.0:80:80 -v /vol/aptrepo-local/nginx/conf/nginx.conf:/etc/nginx/nginx.conf:ro -v /vol/aptrepo-local/repositories:/var/repositories:ro -d nginx

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
    docker exec -it horizon-aptrepo bash -c 'reprepro -b /var/repositories/raspbian copy stretch-updates stretch-testing {blue,}horizon=2.0.17~ppa~raspbian.stretch'
    Exporting indices...

#### List packages in a suite

    docker exec -it horizon-aptrepo bash -c 'reprepro -b /var/repositories/ubuntu list xenial-updates'

### Delete versions

NOTE: This needs to be done for each repository (`ubuntu` in this example) and codename (`xenial-testing` in this example)

List them first with a filter to isolate what you want to delete:

    docker exec -it horizon-aptrepo bash -c 'reprepro -Vb /var/repositories/ubuntu listfilter xenial-testing "Version (== 2.22.8~ppa~ubuntu.xenial)"'

Delete them:

    docker exec -it horizon-aptrepo bash -c 'reprepro -Vb /var/repositories/ubuntu removefilter xenial-testing "Version (== 2.22.8~ppa~ubuntu.xenial)"'

### Add a new 'branch' repo/codename

Edit the conf files:

`/vol/aptrepo-local/repositories/*/conf/distributions`
`/vol/aptrepo-local/repositories/*/conf/incoming`

Export (initialize) new repo(`ubuntu`) and codename(`xenial-la-updates`) for updates:

    docker exec -it horizon-aptrepo bash -c 'reprepro -Vb /var/repositories/ubuntu export xenial-la-updates'

### Delete entire codename contents

NOTE: DANGER!! Do not do this unless you know what you're doing

Remove the codename directory:

    /vol/aptrepo-local/repositories/<repo>/dists/<codename>

Run cleanup:

    docker exec -it horizon-aptrepo bash -c 'reprepro -Vb /var/repositories/<repo> clearvanished'

## aptrepo

Start command:

    docker run --name horizon-reposerv -p 0.0.0.0:80:80 -v /vol/aptrepo-local/nginx/conf/nginx.conf:/etc/nginx/nginx.conf:ro -v /vol/aptrepo-local/repositories:/var/repositories:ro -d nginx

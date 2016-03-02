#!/bin/bash
HOSTPOKYDIR=`readlink -f $1`
shift
LOCAL_VOLUME=`readlink -f $1`
shift

IMAGE_UUID=`uuidgen`

BASEPOKYDIR=copied_pokydir
COPIED_POKYDIR=$LOCAL_VOLUME/$BASEPOKYDIR
CONTAINER_POKYDIR=/home/yoctouser/userpoky/$BASEPOKYDIR
BASECONFDIR=confdir
CONFDIR=$LOCAL_VOLUME/$BASECONFDIR

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

trap signalhandler SIGINT SIGTERM

function signalhandler {
    cleanup
    exit 1
}
function cleanup {
    echo "Cleaning up..."
    containers=`docker ps -a | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'`
    if [ "x$containers" != "x" ]; then
        docker kill -s KILL `docker ps | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'` > /dev/null 2>&1
    fi

    docker wait $containers > /dev/null 2>&1
    docker rm $containers
    docker rmi $IMAGE_UUID
    exit 1
}

function copy_poky_dir() {
    rm -rf $COPIED_POKYDIR
    mkdir -p $COPIED_POKYDIR
    tar --exclude-vcs -c -C `dirname $HOSTPOKYDIR` `basename $HOSTPOKYDIR` | \
            tar -C $COPIED_POKYDIR -x --strip-components=1
}

function create_baseconf() {
    mkdir -p $CONFDIR
    cat << EOF > $CONFDIR/base-extraconf.inc
DISTRO_FEATURES_append = " systemd"
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED = "sysvinit"
DL_DIR = "/fromhost/downloads"

INHERIT += "rm_work"
EOF
}

function create_docker_image {
    MYUID=`id -u`
    MYGID=`id -g`

    echo "Creating docker image"

    contextdir=`mktemp -d`
    cp -r $COPIED_POKYDIR $contextdir

    dockerfile=$contextdir/Dockerfile

    cat << EOF > $dockerfile
FROM rewitt/yocto-testrunner

USER root

COPY $BASEPOKYDIR $CONTAINER_POKYDIR
RUN groupadd -o -g $MYGID yoctogroup && \
    usermod -o -u $MYUID -g $MYGID yoctouser &&\
    chown -R yoctouser:yoctogroup /home/yoctouser

USER yoctouser
EOF

    if ! docker build -f $dockerfile -t $IMAGE_UUID $contextdir; then
        echo "Image creation failed: Exiting..."
        cleanup
	exit 1
    fi
}

function create_testimage_sstate {
    echo "Creating testimage-sstate..."
    mkdir -p $CONFDIR

    mkdir -p $CONFDIR
    cat << EOF > $CONFDIR/testimage-extraconf.inc
SSTATE_DIR = "/fromhost/testimage-sstate-cache"
EOF

    BUILDDIR=`mktemp -d -p $LOCAL_VOLUME youcandeleteme-builddir.XXX`

    # I do not like --net=host, but this is the easiest way to get people up and
    # going without them having to worry about whether things will work behind a
    # proxy.
    docker run --name="container-sstate-gen-$IMAGE_UUID" -t --net=host \
               --privileged -v $LOCAL_VOLUME:/fromhost \
               --entrypoint=/home/yoctouser/runbitbake.py $IMAGE_UUID \
               core-image-sato \
               /fromhost/`basename $BUILDDIR` \
               --pokydir=$CONTAINER_POKYDIR \
               --extraconf=/fromhost/$BASECONFDIR/base-extraconf.inc \
               --extraconf=/fromhost/$BASECONFDIR/testimage-extraconf.inc 

    rm -rf $BUILDDIR
}

mkdir -p $LOCAL_VOLUME

copy_poky_dir

# This is so that the uid/gid fixups happen so after the sstate gets created
# the use on the host will actually be able to access it
create_docker_image

create_baseconf
create_testimage_sstate

cleanup

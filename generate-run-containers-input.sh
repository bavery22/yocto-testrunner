#!/bin/bash
HOSTPOKYDIR=$1
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
    cat << EOF > $CONFDIR/testimage-extraconf.inc
SSTATE_DIR = "/fromhost/testimage-sstate-cache"
EOF

    # I do not like --net=host, but this is the easiest way to get people up and
    # going without them having to worry about whether things will work behind a
    # proxy.
    docker run --name="container-sstate-gen-$IMAGE_UUID" -t --net=host \
               -v $LOCAL_VOLUME:/fromhost $IMAGE_UUID \
               /dev/null \
               "ping" \
               --builddir=/home/yoctouser/build \
               --pokydir=$CONTAINER_POKYDIR \
               --outputprefix=$IMAGE_UUID \
               --extraconf=/fromhost/$BASECONFDIR/base-extraconf.inc \
               --extraconf=/fromhost/$BASECONFDIR/testimage-extraconf.inc \
               > /dev/null 2>&1

    # Remove the failure directory since we know it will fail and don't want
    # to clutter up the local volume. But only do it if it contains the
    # expected failure.
    if grep "ERROR: No package manifest file found. Did you build the image?" $LOCAL_VOLUME/$IMAGE_UUID*-failure/stdout > /dev/null 2>&1 ; then
        rm -rf $LOCAL_VOLUME/$IMAGE_UUID*-failure
    else
        echo "Could not generate sstate, check $IMAGE_UUID*-failure/stdout"
    fi
}

function create_coreimagesato_sstate {
    echo "Creating core-image-sato..."

    mkdir -p $CONFDIR
    cat << EOF > $CONFDIR/image-extraconf.inc
SSTATE_DIR = "/fromhost/image-sstate-cache"
EOF

    BUILDDIR=`mktemp -d -p $LOCAL_VOLUME youcandeleteme-builddir.XXX`

    # I do not like --net=host, but this is the easiest way to get people up and
    # going without them having to worry about whether things will work behind a
    # proxy.
    docker run --name="container-coreimagesato-gen-$IMAGE_UUID" -t --net=host \
               --privileged -v $LOCAL_VOLUME:/fromhost \
               --entrypoint=/home/yoctouser/runbitbake.py $IMAGE_UUID \
               core-image-sato \
               /fromhost/`basename $BUILDDIR` \
               --pokydir=$CONTAINER_POKYDIR \
               --extraconf=/fromhost/$BASECONFDIR/base-extraconf.inc \
               --extraconf=/fromhost/$BASECONFDIR/image-extraconf.inc \
               > /dev/null 2>&1

    DEPLOYDIR=`mktemp -d -p $LOCAL_VOLUME youcandeleteme-deploydir.XXX`
    cp -r $BUILDDIR/tmp/deploy $DEPLOYDIR

    # Shuffle the deploy directory around to make things happy
    mv $DEPLOYDIR/deploy/images $DEPLOYDIR
    mv $DEPLOYDIR/images/qemux86 $DEPLOYDIR/deploy/images

    rm $LOCAL_VOLUME/deploy -rf
    mv $DEPLOYDIR/deploy $LOCAL_VOLUME

    rm -rf $DEPLOYDIR
    rm -rf $BUILDDIR
}

mkdir -p $LOCAL_VOLUME

copy_poky_dir

# This is so that the uid/gid fixups happen so after the sstate gets created
# the use on the host will actually be able to access it
create_docker_image

create_baseconf
create_coreimagesato_sstate
create_testimage_sstate

cleanup

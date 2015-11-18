#!/bin/bash
HOSTPOKYDIR=$1
shift
LOCAL_VOLUME=`readlink -f $1`
shift

IMAGE_UUID=`uuidgen`

BASEPOKYDIR=`basename $HOSTPOKYDIR`
CONTAINER_POKYDIR=/home/yoctouser/userpoky/$BASEPOKYDIR

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function cleanup {
    echo "Cleaning up..."
    while true; do
        containers=`docker ps -a | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'`
        if [ "x$containers" != "x" ]; then
            docker kill -s KILL `docker ps | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'` > /dev/null 2>&1
        else
            break
        fi
    done

    docker wait $containers > /dev/null 2>&1 
    docker rmi $IMAGE_UUID
    exit 1
}

function create_image {
    MYUID=`id -u`
    MYGID=`id -g`

    echo "Creating image"

    contextdir=`mktemp -d`
    cp -r $HOSTPOKYDIR $contextdir

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
    fi
}

# This is so that the uid/gid fixups happen so after the sstate gets created
# the use on the host will actually be able to access it
create_image

function create_testimage_sstate {
    echo "Creating sstate..."
    # I do not like --net=host, but this is the easiest way to get people up and
    # going without them having to worry about whether things will work behind a
    # proxy.
    docker run --name="container-sstate-gen-$IMAGE_UUID" -t --net=host \
               --privileged -v $LOCAL_VOLUME:/fromhost $IMAGE_UUID \
               --uid=${UID} --builddir=/home/yoctouser/build \
               --deploydir=/dev/null dummybranch \
               --pokydir=$CONTAINER_POKYDIR \
               --variable "SSTATE_DIR=/fromhost/sstate-cache"
}

mkdir -p $LOCAL_VOLUME

echo "Creating sstate..."
create_testimage_sstate

docker wait container-sstate-gen-$IMAGE_UUID
docker rmi $IMAGE_UUID

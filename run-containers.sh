#!/bin/bash

IMAGE=$1
shift
NUM_INSTANCES=$1
shift
LOCAL_VOLUME=$1
shift
RUNBUILD_ARGS=$@

# Assume the pokydir must be in /fromhost
if [ -d $LOCAL_VOLUME/copied_pokydir ]; then
    HOST_POKYDIR=$LOCAL_VOLUME/copied_pokydir
    BASEPOKYDIR="`basename $HOST_POKYDIR`"
fi

IMAGE_UUID=`uuidgen`-testing
DEPLOY_DIR_URL="http://yocto-ab-master.jf.intel.com/~rewitt/deploy.tar.xz"
UID=`id -u`
GID=`id -g`
# Default hardlimit on fedora
ulimit -S -u 257070

# Needed since bitbake does tons of watches
sudo sysctl -n -w fs.inotify.max_user_watches=15000000 > /dev/null 2>&1

i=0

iostat -x -z -N -d -p -t ALL 20 > iostat.log &
IOSTAT_PID=$!

function cleanup {
    echo "Cleaning up... may take a while for all containers to stop"
    while true; do
        containers=`docker ps -a | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'`
        if [ "x$containers" != "x" ]; then
            docker kill -s KILL `docker ps | awk -v image="$IMAGE_UUID" '$2 ~ image {print $1}'` > /dev/null 2>&1
        else
            break
        fi
    done

    docker wait $containers > /dev/null 2>&1 
    if [ "x$KEEP_TEST_IMAGE" = "x" ]; then
        docker rmi $IMAGE_UUID
    fi
    kill -9 $IOSTAT_PID
    exit 1
}

trap cleanup SIGINT SIGTERM

function run_container {
    echo "Starting container: $i-$IMAGE_UUID"
    docker run --name="container-$i-$IMAGE_UUID" --rm=true -t --privileged -v $LOCAL_VOLUME:/fromhost $IMAGE_UUID /fromhost/deploy $POKYDIR_ARG --extraconf=/home/yoctouser/local.conf --builddir=/home/yoctouser/build --outputprefix="container-$i-$IMAGE_UUID-" $RUNBUILD_ARGS &
}

function create_deploy_dir {
    # If the directory doesn't exist, or it is empty assume the user is ok with
    # downloading the deploy dir.
    if [ ! -d $LOCAL_VOLUME -o -z "`ls -A $LOCAL_VOLUME`" ]; then
        mkdir -p $LOCAL_VOLUME

        echo "Downloading sstate and images..."
        curl -# $DEPLOY_DIR_URL | tar -C $LOCAL_VOLUME -x -J
    fi
}

function create_image {
    echo "Creating image"

    contextdir=`mktemp -d`

    # Copy the items to the contextdir so not as much data has to be sent to
    # the docker daemon.
    if [ -d $LOCAL_VOLUME/testimage-sstate-cache ]; then
        cp -r $LOCAL_VOLUME/testimage-sstate-cache $contextdir
    else
        mkdir $contextdir/testimage-sstate-cache
    fi

    # We actually put the sstate and image to be tested into the image so that
    # a test can be easily reproduced without the input directory
    if [ -d $LOCAL_VOLUME/confdir ]; then
        cat $LOCAL_VOLUME/confdir/base-extraconf.inc >> $contextdir/local.conf
        cat $LOCAL_VOLUME/confdir/testimage-extraconf.inc >> $contextdir/local.conf
    fi

    echo "SSTATE_DIR = \"/home/yoctouser/testimage-sstate-cache\"" >> $contextdir/local.conf

    # Copying to a new dir named poky rather than preserving the name so
    # that things don't get even more cluttered with basename
    if [ -n "$HOST_POKYDIR" ]; then
        cp -r $HOST_POKYDIR $contextdir
        POKYDIR_ARG="--pokydir=/home/yoctouser/$BASEPOKYDIR"
    else
        BASEPOKYDIR="pokyfromuser"
        mkdir $contextdir/$BASEPOKYDIR
    fi

    dockerfile=$contextdir/Dockerfile
cat << EOF > $dockerfile
FROM $IMAGE

# Creating fromhost is just to capture the logs when running testimage
# fails which we know will
USER root
COPY testimage-sstate-cache /home/yoctouser/testimage-sstate-cache
COPY local.conf /home/yoctouser/local.conf

RUN mkdir /fromhost
COPY $BASEPOKYDIR /home/yoctouser/$BASEPOKYDIR
RUN groupadd -o -g $GID yoctogroup && \
    usermod -o -u $UID -g $GID yoctouser &&\
    chown -R yoctouser:yoctogroup /fromhost /home/yoctouser

USER yoctouser

# Setting deploydir prevents runbuild from trying to build the image
# Also the exit 0 is because we know this command will fail due to
# non-existant image.
RUN /home/yoctouser/runtest.py /dev/null "ping" \
        --builddir=/home/yoctouser/build \
        --extraconf=/home/yoctouser/local.conf \
        $POKYDIR_ARG ; \
        rm /fromhost/* -rf; \
        exit 0
EOF

# If we had to pull a new image keep the newly created image by default. It
# will substantially speed up subsequent runs.
if ! docker pull $IMAGE | grep "^Status: Image is up to date" > /dev/null 2>&1; then
    KEEP_TEST_IMAGE="1"
fi

if ! docker build --force-rm=true -f $dockerfile -t $IMAGE_UUID $contextdir; then
    echo "Image creation failed: Exiting..."
    cleanup
fi
}

create_deploy_dir
create_image

while [ $i -lt $NUM_INSTANCES ]; do
    i=$((i+1))
    run_container
done

while true; do
    wait -n

    i=$((i+1))
    run_container
done

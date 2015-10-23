#!/bin/bash

IMAGE=$1
shift
NUM_INSTANCES=$1
shift
LOCAL_VOLUME=$1
shift
RUNBUILD_ARGS=$@

IMAGE_UUID=`uuidgen`-testing
BRANCH="rewitt/container_testing"
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
    docker run --name="container-$i-$IMAGE_UUID" --rm=true -t --privileged -v $LOCAL_VOLUME:/fromhost $IMAGE_UUID --uid=${UID} --builddir=/home/yoctouser/build --deploydir=/fromhost/deploy --outputprefix="container-$i-$IMAGE_UUID-" $BRANCH $RUNBUILD_ARGS &
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

    # Copy the sstate to the contextdir so not as much data has to be sent to
    # the docker daemon.
    cp -r $LOCAL_VOLUME/sstate-cache $contextdir

    dockerfile=$contextdir/Dockerfile
cat << EOF > $dockerfile
FROM $IMAGE

# Creating fromhost is just to capture the logs when running testimage
# fails which we know will
USER root
COPY sstate-cache /home/yoctouser/sstate-cache
RUN groupadd -o -g $GID yoctogroup && \
    usermod -o -u $UID -g $GID yoctouser &&\
    mkdir /fromhost &&\
    chown -R yoctouser:yoctogroup /fromhost /home/yoctouser/sstate-cache

USER yoctouser

# Setting deploydir prevents runbuild from trying to build the image
# Also the exit 0 is because we know this command will fail due to
# non-existant image.
RUN /home/yoctouser/runbuild.py rewitt/container_testing \
        --builddir=/home/yoctouser/build \
        --deploydir=/dev/null; \
        rm /fromhost/* -rf; \
        exit 0
EOF

if ! docker build --pull=true --force-rm=true -f $dockerfile -t $IMAGE_UUID $contextdir; then
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

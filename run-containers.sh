#!/bin/bash

IMAGE=$1
NUM_INSTANCES=$2

# Default hardlimit on fedora
ulimit -S -u 257070

# Needed since bitbake does tons of watches
sudo sysctl -n -w fs.inotify.max_user_watches=15000000

i=0

iostat -x -z -N -d -p ALL 20 > iostat.log &
IOSTAT_PID=$!

trap "kill -9 $IOSTAT_PID; exit 1;" SIGINT

function run_container {
    echo "Starting container: $i"
    sudo docker run -t --rm=true --uid=`id -u` --privileged -v /stub:/fromhost $IMAGE master --testsuites='ping' --deploydir=/fromhost/deploy --preservesuccess &
}

while [ $i -lt $NUM_INSTANCES ]; do
    i=$((i+1))
    run_container
done

while true; do
    wait -n
    i=$((i+1))
    run_container
done

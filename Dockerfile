FROM rewitt/yocto:ubuntu-14.04-builder

USER root
RUN echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifdown" >> /etc/sudoers && \
    apt-get update && \
    apt-get install -y \
        iptables && \
    apt-get clean

USER yoctouser
COPY local.conf /home/yoctouser/

WORKDIR /home/yoctouser

# The specific committish is specified to invalidate the docker cache and
# make sure the image is updated. If the branch was used, docker would not
# update the image.
RUN  git clone --depth=1 --branch=rewitt/container_testing \
         http://git.yoctoproject.org/git/poky-contrib poky && \
     cd poky && \
     git reset --hard e88ac996cd645e7b1943a3beb7a98ac72d30cf33 && \
     git gc --aggressive --prune=all
 

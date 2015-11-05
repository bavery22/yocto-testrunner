FROM rewitt/yocto:ubuntu-14.04-builder

USER root

# This isn't for security. Although everything could be nopasswd, at least try
# to make things somewhat explicit.
RUN echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifdown" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /fromhost/*/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /fromhost/*/scripts/runqemu-ifdown" >> /etc/sudoers && \
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
     git reset --hard f696ea8793588e23f585f7b709f2acbdf79dd5a7 && \
     git gc --aggressive --prune=all
 

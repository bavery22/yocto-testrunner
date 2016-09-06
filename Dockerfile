FROM crops/yocto:ubuntu-14.04-builder

USER root

# This isn't for security. Although everything could be nopasswd, at least try
# to make things somewhat explicit.
RUN echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /home/yoctouser/poky/scripts/runqemu-ifdown" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /home/yoctouser/copied_pokydir/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /home/yoctouser/copied_pokydir/scripts/runqemu-ifdown" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /fromhost/*/scripts/runqemu-ifup" >> /etc/sudoers && \
    echo "yoctouser ALL=NOPASSWD: /fromhost/*/scripts/runqemu-ifdown" >> /etc/sudoers && \
    apt-get update && \
    apt-get install -y \
        iptables && \
    apt-get clean

COPY runtest.py /home/yoctouser/
RUN chmod +x /home/yoctouser/runtest.py

USER yoctouser

WORKDIR /home/yoctouser
ENTRYPOINT ["/home/yoctouser/runtest.py"]

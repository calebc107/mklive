#!/bin/bash
echo "
deb http://deb.debian.org/debian buster main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
" > /etc/apt/sources.list
apt update
apt install -t debian-backports linux-image-amd64 firmware-misc-nonfree firmware-iwlwifi
apt install live-boot sudo locales-all
dpkg-reconfigure locales-all
update-initramfs.orig.initramfs-tools -ck $(ls /lib/modules | tail -n 1)
passwd -d root

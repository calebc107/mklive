#!/bin/bash
echo "deb http://deb.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list
apt update
apt install live-boot linux-image-amd64 sudo locales-all firmware-misc-nonfree
dpkg-reconfigure locales-all
update-initramfs.orig.initramfs-tools -ck $(ls /lib/modules | tail -n 1)
passwd -d root

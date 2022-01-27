#!/bin/bash
set -e
echo "
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-backports main contrib non-free
deb-src http://deb.debian.org/debian bullseye-backports main contrib non-free
" > /etc/apt/sources.list
apt update
#TODO: re-instate backports as soon as packages are available for it
#apt install -t bullseye-backports linux-image-amd64 network-manager firmware-iwlwifi firmware-brcm80211 firmware-atheros firmware-ralink firmware-realtek
apt install linux-image-amd64 network-manager firmware-iwlwifi firmware-brcm80211 firmware-atheros firmware-ralink firmware-realtek
apt install linux-image-amd64 network-manager firmware-iwlwifi firmware-brcm80211 firmware-atheros firmware-ralink firmware-realtek
apt install live-boot sudo locales-all
read -p "Set new hostname: " newhostname
echo $newhostname > /etc/hostname
cat /etc/hostname
cat << END > /etc/hosts
127.0.0.1	localhost
127.0.1.1	$newhostname
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
END
cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
END
dpkg-reconfigure locales-all
update-initramfs.orig.initramfs-tools -ck $(ls /lib/modules | tail -n 1)
passwd -d root

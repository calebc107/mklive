#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi
apt install debootstrap squashfs-tools
mkdir -p output
if [ ! -d ./live ]; then
debootstrap bullseye ./live/
read -p "Set new hostname: " newhostname
echo $newhostname > ./live/etc/hostname
cat ./live/etc/hostname
cat << END > ./live/etc/hosts
127.0.0.1	localhost
127.0.1.1	$newhostname
END
fi

cp update.sh ./live/
chmod +x ./live/update.sh
systemd-nspawn -D ./live /update.sh #chroot ./live/ /update.sh
mv live/mnt/* output/
chmod 755 ./output/*
echo "
Live system initialized.
NEXT STEPS:
	Copy new files from output/ to removable media and ensure threre is a grub config for it"
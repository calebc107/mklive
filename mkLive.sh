#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi
apt install debootstrap squashfs-tools
umount ./live/dev -l || true #unsure why -l works
umount ./live/proc || true
umount ./live/sys || true
umount ./live/mnt || true
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
mount --bind /dev ./live/dev
mount --bind /proc ./live/proc
mount --bind /sys ./live/sys
mount --bind ./output ./live/mnt
chroot ./live/ /update.sh
umount -l ./live/dev
umount ./live/proc
umount ./live/sys
umount ./live/mnt
chmod 755 ./output/*
echo "
Live system initialized.
NEXT STEPS:
	Copy new files from output/ to removable media and ensure threre is a grub config for it"
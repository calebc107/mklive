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
umount -l ./live/dev
umount ./live/proc
umount ./live/sys
mksquashfs ./live/ filesystem.squashfs -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'
cp ./live/boot/vmlinuz* ./vmlinuz
cp ./live/boot/initrd* ./initrd.img
chmod 755 ./vmlinuz ./initrd.img filesystem.squashfs
echo "
Live system initialized.
NEXT STEPS:
	Copy new files to removable media
	Boot into new system
	Login with username root on tty2
	Execute \"/update.sh {path-to-live-medium}\""

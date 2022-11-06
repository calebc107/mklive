#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi
apt install debootstrap squashfs-tools
umount ./live/dev || true
umount ./live/proc || true
umount ./live/sys || true
rm -r live || true
debootstrap $distro ./live/

cp ./distros/$distro/chroot.sh ./live/chroot.sh
cp ./distros/$distro/update.sh ./live/update.sh
chmod +x ./live/chroot.sh
chmod +x ./live/update.sh
mount --bind /dev ./live/dev
mount --bind /proc ./live/proc
mount --bind /sys ./live/sys
chroot ./live/ /chroot.sh
umount ./live/dev
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

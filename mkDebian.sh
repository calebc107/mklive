#!/bin/bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
apt install debootstrap squashfs-tools
rm -r live
mkdir live
debootstrap buster ./live/
echo "#!/bin/bash
echo \"deb http://deb.debian.org/debian buster main contrib non-free\" > /etc/apt/sources.list
apt update
apt dist-upgrade
apt install live-boot linux-image-amd64 sudo locales-all firmware-misc-nonfree
dpkg-reconfigure locales-all
update-initramfs.orig.initramfs-tools -ck \$(ls /lib/modules | tail -n 1)
passwd -d root" > ./live/chroot.sh
cp updateDebian.sh ./live/update.sh
chmod +x ./live/update.sh
chmod +x ./live/chroot.sh
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
chmod 777 ./vmlinuz ./initrd.img filesystem.squashfs
chown caleb:caleb ./vmlinuz ./initrd.img filesystem.squashfs
echo "Live system initialized.
NEXT STEPS:
	Copy new files to removable media
	Boot into new system
	Login with username root on tty2
	Execute \"/update.sh {path-to-live-medium}\""

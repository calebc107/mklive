#!/bin/bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
apt install debootstrap squashfs-tools
rm -r live
mkdir live
debootstrap stretch ./live/
echo "#!/bin/bash
echo \"deb http://deb.debian.org/debian stretch main contrib non-free\" > /etc/apt/sources.list
apt update
apt dist-upgrade
apt install gnome-core chromium live-boot linux-image-amd64 sudo locales-all bash-completion nvidia-driver
apt autoremove
apt autoclean

read -p \"Type username: \" user
adduser \$user
adduser \$user sudo" > ./live/chrootDebian.sh
chmod +x ./live/chrootDebian.sh
mount --bind /dev ./live/dev
mount --bind /proc ./live/proc
mount --bind /sys ./live/sys
chroot ./live/ /chrootDebian.sh
umount ./live/dev
umount ./live/proc
umount ./live/sys
mksquashfs ./live/ filesystem.squashfs -noappend
cp ./live/boot/vmlinuz* ./vmlinuz
cp ./live/boot/initrd* ./initrd.img
chmod 777 ./vmlinuz ./initrd.img filesystem.squashfs

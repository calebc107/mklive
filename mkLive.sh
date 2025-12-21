#!/bin/bash -e
[ "$EUID" -ne 0 ] && exec sudo $0 $@

mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory

[ -d debootstrap ] || git clone https://salsa.debian.org/installer-team/debootstrap.git

mkdir -p debian_live
if [ ! -d ./debian_chroot ]; then
    DEBOOTSTRAP_DIR=debootstrap debootstrap/debootstrap --arch amd64 trixie ./debian_chroot/
    cd debian_chroot
    read -p "Set hostname for debian: " newhostname
    echo $newhostname > ./etc/hostname
    cat << END > ./etc/hosts
127.0.0.1 localhost
127.0.1.1 $newhostname
END
    cd ..
fi

cp update-debian.sh ./debian_chroot/usr/bin/live-update
chmod +x ./debian_chroot/usr/bin/live-update
systemd-nspawn -D ./debian_chroot /usr/bin/live-update --chroot #run update script inside chroot
mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory

mkdir -p debian_live
mv debian_chroot/filesystem.squashfs debian_chroot/initrd.img debian_chroot/vmlinuz debian_live/
chmod 755 debian_live/*
echo "
Live system initialized.
NEXT STEPS:
	Copy new files from debian_live/ to removable media and ensure threre is a grub config for it"
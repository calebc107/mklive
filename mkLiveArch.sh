#!/bin/bash
# steps modified from Arch wiki at 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_tarball_(recommended)
# and https://wiki.archlinux.org/title/installation_guide

set -e
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi

mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory

#create arch chroot
if [ ! -d arch_chroot ]; then #download bootstrap tar if needed
    if [ ! -e  archlinux-bootstrap-x86_64.tar.zst ]; then
        wget https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst -O archlinux-bootstrap-x86_64.tar.zst
    fi
    mkdir arch_chroot
    cd arch_chroot
    tar -xf ../archlinux-bootstrap-x86_64.tar.zst --numeric-owner
    mv root.x86_64/* . 
    rm -rf root.x86_64
    read -p "Set hostname for arch: " newhostname
    echo $newhostname > ./etc/hostname
    cat << END > ./etc/hosts
127.0.0.1 localhost
127.0.1.1 $newhostname
END
    cd ..
fi

cp update-arch.sh ./arch_chroot
chmod +x ./arch_chroot/update-arch.sh
umount arch_chroot || true
mount --bind arch_chroot arch_chroot
./arch_chroot/bin/arch-chroot arch_chroot /update-arch.sh --chroot #run update script inside chroot
mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory

mkdir -p  output_arch
mv arch_chroot/vmlinuz-linux output_arch/vmlinuz-linux
mv arch_chroot/initramfs-linux.img output_arch/initramfs-linux.img
mv arch_chroot/filesystem.esquashfs output_arch/filesystem.esquashfs
chmod 755 output_arch/* 
echo "
Live system initialized.
NEXT STEPS:
	Copy new files from output_arch/ to removable media and ensure threre is a grub config for it"


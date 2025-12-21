#!/bin/bash -e
# steps modified from Arch wiki at 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_tarball_(recommended)
# and https://wiki.archlinux.org/title/installation_guide

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

cp update-arch.sh ./arch_chroot/usr/bin/live-update
chmod +x ./arch_chroot/usr/bin/live-update
mount --bind arch_chroot arch_chroot
./arch_chroot/bin/arch-chroot arch_chroot /usr/bin/live-update --chroot #run update script inside chroot
mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory

mkdir -p arch
mv arch_chroot/vmlinuz-linux arch_livevmlinuz-linux
mv arch_chroot/initramfs-linux-live.img arch_liveinitramfs-linux-live.img
mv arch_chroot/filesystem.esquashfs arch_livefilesystem.esquashfs
chmod 755 arch_live*
echo "
Live system initialized.
NEXT STEPS:
	Done! Copy arch_live directory to removable media"
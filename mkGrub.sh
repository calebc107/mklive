#!/bin/bash -ex
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi

if [[ "$1" == "" ]]; then
	echo "you must specify a device to install to"
	exit 1
fi


mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory
losetup | grep $PWD | cut -d' ' -f 1 | xargs -n1 losetup -d || true #clear any loopbacks

DEV=$1

#setup loopback if destination is a file
if [ -f $DEV ]; then
	FILE=$DEV
	DEV=$(losetup -f)
	echo "setting up loopback on $DEV for file $FILE"
	losetup -P $DEV $FILE
fi

#add partition number 
PART=$DEV
if [[ $DEV = *[0-9] ]];then PART="${PART}p";fi
PART="${PART}1"


read -p "Installing to $DEV, and partition $PART. Press enter to continue."


[ -d debootstrap ] || git clone https://salsa.debian.org/installer-team/debootstrap.git

if [ ! -d ./grub_build_chroot ]; then
	mkdir -p grub_build_chroot
    DEBOOTSTRAP_DIR=debootstrap debootstrap/debootstrap --arch amd64 trixie ./grub_build_chroot/
    cd grub_build_chroot
    echo "grub_build" > ./etc/hostname
    cat << END > ./etc/hosts
127.0.0.1 localhost
127.0.1.1 grub_build
END
    cd ..
fi

for nod in $DEV $PART /dev/loop-control; do
	touch ./grub_build_chroot$nod
	mount --bind $nod ./grub_build_chroot$nod
done
mount -t proc -o ro proc ./grub_build_chroot/proc
mount -t sysfs -o ro sys ./grub_build_chroot/sys
# mount --bind $DEV ./grub_build_chroot$DEV
# mount --bind $PART ./grub_build_chroot$PART
chroot ./grub_build_chroot bash -ex << END
PATH=\$PATH:/usr/sbin
mkdir -p /efi
mount $PART /efi
apt update
apt install -y memtest86+ efi-shell-x64 grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed
grub-install --removable --boot-directory /efi/boot --target x86_64-efi --force --skip-fs-probe --efi-directory /efi --no-nvram --uefi-secure-boot $DEV
grub-install --boot-directory=/efi/boot --target=i386-pc $DEV
[ -f memtest64.bin ] || curl https://www.memtest.org/download/v7.20/mt86plus_7.20.binaries.zip | bsdtar -xvf -
mkdir -p efi/tools
cp /boot/memtest86+* /usr/share/efi-shell-x64/shellx64.efi efi/tools
cat << 'EOF' > efi/boot/grub/grub.cfg
set check_signatures=no
set gfxmode=auto
insmod all_video
if [ \$grub_platform = efi ]; then
	insmod efi_gop
	insmod efi_uga
else
	insmod vbe
	insmod vga
fi
insmod video_bochs
insmod video_cirrus
insmod gfxterm
loadfont unicode
insmod gettext
terminal_output gfxterm
set default=1
set timeout=20

probe -u \$root --set=rootuuid

menuentry "Platform: \$grub_platform" {
	echo
}

menuentry "Continue Startup" {
	exit
}

menuentry "Debian 13 64-bit"{
	linux /debian_live/vmlinuz boot=live live-media-path=/debian_live ignore_uuid
	initrd /debian_live/initrd.img
}

menuentry "Arch 64-bit"{
        linux /arch_live/vmlinuz-linux rd.systemd.mount-extra=UUID=\$rootuuid:/run/live/medium:auto:defaults,ro SYSTEMD_SULOGIN_FORCE=1
        initrd /arch_live/initramfs-linux-live.img
}
if [ cpuid -l ]; then # 64 bit
	if [ \$grub_platform = efi ]; then
		menuentry "Memtest86+ 64 bit (EFI)"{
			linux /tools/memtest86+x64.efi
		}
	else
		menuentry "Memtest86+ 64 bit (BIOS)"{
			linux /tools/memtest86+x64.bin
		}
	fi
else
	if [ \$grub_platform = efi ]; then
		menuentry "Memtest86+ 32 bit (EFI)"{
			linux /tools/memtest86+ia32.efi
		}
	else
		menuentry "Memtest86+ 32 bit (BIOS)"{
			linux /tools/memtest86+ia32.bin
		}
	fi
fi

if [ \$grub_platform = efi ]; then
	menuentry "MOKManager"{
		chainloader /EFI/boot/mmx64.efi
	}
	menuentry "EFI Shell" {
		chainloader /EFI/boot/shellx64.efi
	}

	menuentry "EFI Setup" {
		fwsetup
	}
fi

menuentry "Reboot" {
	reboot
}

menuentry "Power Off" {
	halt
}
EOF
sync
umount /efi
END

mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory
losetup | grep $PWD | cut -d' ' -f 1 | xargs -n1 losetup -d #clear any loopbacks

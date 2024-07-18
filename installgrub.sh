#!/bin/bash

if [ $(id -u) -ne 0 ]; then
    sudo $0 $@
    exit
fi
cd $(dirname $0)
DEV=$1
PART=$DEV
if [[ $DEV = *[0-9] ]];then PART="${PART}p";fi
PART="${PART}1"
read -p "Installing to $DEV. Press enter to continue."
apt install grub-efi-amd64-signed grub-pc
mkdir -p mnt
mount $PART ./mnt
grub-install --boot-directory ./mnt/boot --target i386-pc $DEV
grub-install --removable --boot-directory ./mnt/boot --target x86_64-efi --uefi-secure-boot --disable-shim-lock --efi-directory ./mnt --no-nvram $DEV 
cp memtestx*.bin shellx64.efi mnt/EFI/boot
rm mnt/EFI/boot/fb*.efi

cat << END > mnt/boot/grub/grub.cfg
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


menuentry "Platform: \$grub_platform" {
	echo
}

menuentry "Continue Startup" {
	exit
}

menuentry "Debian 11 64-bit"{
	linux /Debian/vmlinuz boot=live live-media-path=/Debian ignore_uuid
	initrd /Debian/initrd.img
}

menuentry "Memtest86+ 64 bit"{
    linux /EFI/boot/memtestx64.bin
}

menuentry "Memtest86+ 32 bit"{
    linux /EFI/boot/memtestx32.bin
}

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
END


umount ./mnt

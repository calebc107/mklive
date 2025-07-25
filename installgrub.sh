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
grub-install --removable --boot-directory ./mnt/boot --target x86_64-efi --uefi-secure-boot --disable-shim-lock --force --skip-fs-probe --efi-directory ./mnt --no-nvram $DEV 
cp memtestx*.bin shellx64.efi mnt/EFI/boot
rm mnt/EFI/boot/fb*.efi

cat << 'END' > mnt/boot/grub/grub.cfg
set check_signatures=no
set gfxmode=auto
insmod all_video
if [ $grub_platform = efi ]; then
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

probe -u $root --set=rootuuid

menuentry "Platform: $grub_platform" {
	echo
}

menuentry "Continue Startup" {
	exit
}

menuentry "Debian 12 64-bit"{
	linux /Debian/vmlinuz boot=live live-media-path=/Debian ignore_uuid
	initrd /Debian/initrd.img
}

menuentry "Arch 64-bit"{
        linux /arch/vmlinuz-linux live.diskuuid=B894-DB7A live.squashfspath=arch/filesystem.esquashfs
        initrd /arch/initramfs-linux.img
}
if [ cpuid -l ]; then # 64 bit
        if [ $grub_platform = efi ]; then
                menuentry "Memtest86+ 64 bit (EFI)"{
                linux /tools/memtest64.efi
                }
        else
                menuentry "Memtest86+ 64 bit (BIOS)"{
                linux /tools/memtest64.bin
}
        fi
else
        if [ $grub_platform = efi ]; then
                menuentry "Memtest86+ 32 bit (EFI)"{
                linux /tools/memtest32.efi
                }
        else
                menuentry "Memtest86+ 32 bit (BIOS)"{
                linux /tools/memtest32.bin
}
        fi
fi

if [ $grub_platform = efi ]; then
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

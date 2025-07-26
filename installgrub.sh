#!/bin/bash -e
SCRIPT_DIR=$(realpath $(dirname $0))
cd $SCRIPT_DIR

[ -d grub-src ] || git clone https://git.savannah.gnu.org/git/grub.git grub-src
[ -f memtest64.bin ] || curl https://www.memtest.org/download/v7.20/mt86plus_7.20.binaries.zip | bsdtar -xvf -

cd grub-src
[ -f unifont-16.0.04.pcf ] || curl https://mirrors.kernel.org/gnu/unifont/unifont-16.0.04/unifont-16.0.04.pcf.gz | zcat > unifont-16.0.04.pcf
[ -d dejavu-fonts-ttf* ] || curl -L http://sourceforge.net/projects/dejavu/files/dejavu/2.37/dejavu-fonts-ttf-2.37.tar.bz2 | tar -xj
[ -f configure ]||./bootstrap
[ -f Makefile ]|| ./configure --with-unifont=unifont-16.0.04.pcf --with-dejavufont=dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf
[ -f grub-install ]|| make -j16


cd $SCRIPT_DIR

if [ $(id -u) -ne 0 ]; then
    sudo $0 $@
    exit
fi

DEV=$1
PART=$DEV
if [[ $DEV = *[0-9] ]];then PART="${PART}p";fi
PART="${PART}1"
read -p "Installing to $DEV, and partition $PART. Press enter to continue."

mkdir -p mnt
umount mnt || true
mount $PART ./mnt
mkdir -p mnt/tools
./grub-src/grub-install -d ./grub-src/grub-core --boot-directory ./mnt/boot --target i386-pc $DEV
./grub-src/grub-install -d ./grub-src/grub-core --removable --boot-directory ./mnt/boot --target x86_64-efi --disable-shim-lock --force --skip-fs-probe --efi-directory ./mnt --no-nvram $DEV 
cp memtest*.* shellx64.efi mnt/tools

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
        linux /arch/vmlinuz-linux live.diskuuid=$rootuuid live.squashfspath=arch/filesystem.esquashfs
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

#!/bin/bash -ex
[ "$EUID" -ne 0 ]&& exec sudo $0 $@

if [[ "$1" == "" ]]; then
	echo "you must specify a device to install to"
	exit 1
fi

umountall(){
    mount | grep $PWD | cut -d' ' -f 3 | xargs umount -l || true #unmount everything related to this directory
    losetup | grep $PWD | cut -d' ' -f 1 | xargs -n1 losetup -d || true #clear any loopbacks
}

umountall

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

[ -d grub_chroot ] || debootstrap --variant=minbase --components=main --arch=amd64 trixie grub_chroot

./arch_chroot/bin/arch-chroot ./grub_chroot bash -lex << END
apt update
apt upgrade -y
apt install -y busybox-static cpio xz-utils curl grub-pc-bin grub-efi memtest86+ efi-shell-x64 efibootmgr linux-image-amd64 mokutil
mkdir -p /efi
mount $PART /efi
grub-install --target x86_64-efi --boot-directory /efi/boot --removable --force --skip-fs-probe --efi-directory /efi --no-nvram $DEV
grub-install --target i386-pc    --boot-directory /efi/boot $DEV
mkdir -p efi/tools efi/debian 
cp /boot/memtest86+* /usr/share/efi-shell-x64/shellx64.efi efi/tools

for arch in amd64 arm64 armhf i386 loong64 ppc64el riscv64 s390x; do
	[ -f efi/tools/busybox.\$arch ] && continue
	curl "http://ftp.debian.org/debian/pool/main/b/busybox/busybox-static_1.37.0-10_\$arch.deb" | \
	dpkg --fsys-tarfile /dev/stdin | \
	tar xO ./usr/bin/busybox > efi/tools/busybox.\$arch
done

#make busybox initrd
cp -L /vmlinuz efi/debian/vmlinuz #copy kernel
rm -rf busybox_initramfs
mkdir -p busybox_initramfs
uname=\$(echo /lib/modules/*/modules.dep|cut -d/ -f4)
cd busybox_initramfs
mkdir -p bin dev etc lib lib64 proc sys
cat << EOF | xargs -i cp -L --parents {} ./
/lib/x86_64-linux-gnu/libcrypto.so.3
/lib/x86_64-linux-gnu/libefivar.so.1
/lib/x86_64-linux-gnu/libkeyutils.so.1
/lib/x86_64-linux-gnu/libcrypt.so.1
/lib/x86_64-linux-gnu/libc.so.6
/lib/x86_64-linux-gnu/libz.so.1
/lib/x86_64-linux-gnu/libzstd.so.1
/lib64/ld-linux-x86-64.so.2
/bin/mokutil
/bin/busybox
EOF

MODULES="efivarfs evdev usbhid hid-generic xhci-hcd ehci-hcd uhci-hcd ohci-hcd xhci-pci ehci-pci uhci-pci ohci-pci"
echo \$MODULES|xargs modprobe -aS \$uname --show-depends |cut -d" " -f2 | xargs -i cp --parents {} ./
depmod -ab . \$uname


cat << EOF > init
#!/bin/busybox sh
/bin/busybox --install -s /bin
modprobe -av \$MODULES
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
/bin/sh
poweroff -f
EOF
chmod +x init

find . -print0 | cpio --null -ov --format=newc | gzip -9 > /efi/debian/busybox.img
cd /

#write grub config
cat << 'EOF' > efi/boot/grub/grub.cfg
set default=1
set timeout=20
set gfxmode=auto
set gfxpayload=keep
set check_signatures=no
insmod all_video
insmod gfxterm
insmod gettext
loadfont unicode
terminal_output gfxterm

probe -u \$root --set=rootuuid

menuentry "Platform: \$grub_platform" {
	echo
}

menuentry "Continue Startup" {
	exit
}

menuentry "Arch 64-bit"{
        linux /arch_live/vmlinuz-linux rd.systemd.mount-extra=UUID=\$rootuuid:/run/live/medium:auto:defaults,ro SYSTEMD_SULOGIN_FORCE=1
        initrd /arch_live/initramfs-linux-live.img
}

menuentry "Debian busybox"{
        linux /debian/vmlinuz
        initrd /debian/busybox.img
}

if [ \$grub_platform = efi ]; then
	menuentry "Memtest86+ 64 bit (EFI)"{
		linux /tools/memtest86+x64.efi
	}
	menuentry "MOKManager"{
		chainloader /EFI/boot/mmx64.efi
	}
	menuentry "EFI Shell" {
		chainloader /tools/shellx64.efi
	}
	menuentry "EFI Setup" {
		fwsetup
	}
else
	menuentry "Memtest86+ 64 bit (BIOS)"{
		linux /tools/memtest86+x64.bin
	}
fi

menuentry "Reboot" {
	reboot
}

menuentry "Power Off" {
	halt
}
EOF
umount /efi
sync
END

umountall

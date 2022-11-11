#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  sudo $0 $@
  exit
fi

if [ "$(mount | grep ' / ')" = "" ]
then 
  IS_CHROOT=true
  path=/mnt
else
  IS_CHROOT=false
  path=$(dirname $(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6));
fi

echo "is chroot=$IS_CHROOT"
echo "path=$path"
sleep 2

if [ -e /usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  ln -sf /usr/sbin/update-initramfs.orig.initramfs-tools /usr/sbin/update-initramfs
fi

echo "
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-backports main contrib non-free
deb http://deb.debian.org/debian/ bullseye-updates main contrib non-free
deb http://security.debian.org/ bullseye-security main contrib non-free
" > /etc/apt/sources.list

apt update
apt -y dist-upgrade
apt install -y linux-image-amd64 network-manager locales

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

apt install -y firmware-ath9k-htc firmware-atheros firmware-b43-installer firmware-b43-installer \
  firmware-bnx2 firmware-brcm80211 firmware-cavium firmware-intelwimax firmware-ipw2x00 \
  firmware-iwlwifi firmware-libertas firmware-linux* firmware-misc-nonfree \
  firmware-myricom firmware-netronome firmware-ralink firmware-realtek \
  firmware-ti-connectivity firmware-zd1211

apt install -y gparted lshw iperf3 avahi-daemon \
    gnome-core nano bash-completion git htop squashfs-tools net-tools curl wget \
    live-boot sudo systemd-timesyncd alsa-utils pulseaudio grub2 grub-pc \
    grub-efi-amd64-signed testdisk iotop

apt autoremove
apt autoclean

if [ -e /usr/sbin/update-initramfs.orig.initramfs-tools ]; then
  ln -sf /usr/sbin/update-initramfs.orig.initramfs-tools /usr/sbin/update-initramfs
fi

update-initramfs -ck $(ls -v /lib/modules | tail -n 1)

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock -s --localtime
systemctl enable systemd-timesyncd

#allow user to switch to ramdisk if needed
cat << END > /bin/live-toram
#!/bin/bash
path=\$(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6)
echo Copying \$path to memory.
rsync -a --progress \$path /tmp/live
python3 << EOF
import fcntl
loop = open('/dev/loop0')
dest = open('/tmp/live')
fcntl.ioctl(loop,0x4C06,dest.fileno())
loop.close()
dest.close()
EOF
umount \$(df \$path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6)
END

read -p "Type username: " user
adduser $user || true
adduser $user sudo

#set various gnome settings
sudo -u $user dbus-launch dconf load /org/gnome/ << END
[settings-daemon/plugins/media-keys]
custom-keybindings=['/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']
[settings-daemon/plugins/media-keys/custom-keybindings/custom0]
binding='<Primary><Alt>t'
command='gnome-terminal'
name='Terminal'
[settings-daemon/peripherals/keyboard]
numlock-state='on'
[settings-daemon/plugins/media-keys]
custom-keybindings=['/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']
[settings-daemon/plugins/media-keys/custom-keybindings/custom0]
binding='<Primary><Alt>t'
command='gnome-terminal'
name='terminal'
[shell]
favorite-apps=['firefox-esr.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.Terminal.desktop']
[nautilus/preferences]
default-folder-viewer='icon-view'
[nautilus/icon-view]
default-zoom-level='standard'
[desktop/interface]
clock-show-seconds=true
gtk-theme='Adwaita-dark'
[desktop/peripherals/touchpad]
tap-to-click=true
END

cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
END

umount -l /home/$user || true
rm -rf /var/log/journal/* /usr/share/doc # remove some bloat
find {/usr/share/locale/,/usr/share/help/} -mindepth 1 -maxdepth 1 -not -name "en" -exec rm -r {} \; #remove all locales but en

$IS_CHROOT || mount -o remount,rw $(df $path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6);
$IS_CHROOT || mount -f -o remount,ro /
shopt -s dotglob
mksquashfs / $path/newfilesystem.squashfs -comp xz -Xbcj x86 -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'usr/lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'
cp `ls -v /boot/initrd* | tail -n 1` $path/newinitrd.img
cp `ls -v /boot/vmlinuz* | tail -n 1` $path/newvmlinuz

read -p "Press enter to commit changes"
mv $path/newfilesystem.squashfs $path/filesystem.squashfs
mv $path/newinitrd.img $path/initrd.img
mv $path/newvmlinuz $path/vmlinuz
$IS_CHROOT || (echo "unmounting root..."; umount -l /)
$IS_CHROOT || (read -p "Press enter to reboot"; reboot -f)
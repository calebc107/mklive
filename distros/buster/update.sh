#!/bin/bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

path=$1
read -p "Path is $path. Press enter if this is correct and script is running from tty2." continue

mv /usr/sbin/update-initramfs.* /usr/sbin/update-initramfs

echo "
deb http://deb.debian.org/debian buster main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb http://security.debian.org/ buster/updates main contrib non-free
" > /etc/apt/sources.list
apt update
apt dist-upgrade
apt install gparted lshw iperf3 avahi-daemon gnome-core chromium nano bash-completion git htop squashfs-tools net-tools curl wget
apt install -t buster-backports nvidia-driver firmware-amd-graphics firmware-linux-* firmware-misc-nonfree
apt autoremove
apt autoclean

timedatectl set-timezone America/New_York
timedatectl set-local-rtc 1
timedatectl set-ntp 1
mount -o remount,rw /lib/live/mount/medium

#allow user to go to ram if needed
echo "#!/bin/bash
echo \"Copying filesystem to memory.\"
rsync -a --progress $path/filesystem.squashfs /tmp/live

LANGUAGE=C LANG=C LC_ALL=C perl << EOF
open LOOP, '</dev/loop0' or die \$!;
open DEST, '</tmp/live' or die \$!;
ioctl(LOOP, 0x4C06, fileno(DEST)) or die \$!
close LOOP;
close DEST;
EOF

umount /lib/live/mount/medium
"> /bin/live-toram

read -p "Type username: " user
adduser $user
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
[shell]
favorite-apps=['chromium.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.Terminal.desktop']
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

pkill -9 -u $user
umount -l /home/$user
rm -r /var/log/journal/*
rm -r /var/apt/lists/*
apt clean

passwd -l root


shopt -s dotglob
mksquashfs / $path/newfilesystem.squashfs -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'usr/lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'
#cp /boot/initrd.img* $path/newinitrd.img
cp `ls /boot/initrd* | tail -n 1` $path/newinitrd.img
#cp /boot/vmlinuz* $path/newvmlinuz
cp `ls /boot/vmlinuz* | tail -n 1` $path/newvmlinuz

read -p "Press enter to commit changes" continue
mv $path/newfilesystem.squashfs $path/filesystem.squashfs
mv $path/newinitrd.img $path/initrd.img
mv $path/newvmlinuz $path/vmlinuz
umount -l /
read -p "Unmounted all filesystems including root. Press enter to force reboot" continue
reboot -f

#!/bin/bash
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

path=$1
read -p "Path is $path. Press enter if this is correct and script is running from tty2." continue

dhclient
mv /usr/sbin/update-initramfs.* /usr/sbin/update-initramfs

apt update
apt dist-upgrade

apt install gnome-core chromium nano bash-completion ecryptfs-utils
apt remove firefox

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
adduser --encrypt-home $user
adduser $user sudo

read -p "User created. Log in (on another terminal) to new user and make any changes and customizations, then LOG OUT, return to this terminal session and press enter." continue

pkill -9 -u $user
umount.ecryptfs -l /home/$user
rm -r /var/log/journal/*
rm -r /var/apt/lists/*
apt clean

passwd -l root


shopt -s dotglob
mksquashfs / $path/newfilesystem.squashfs -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'
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

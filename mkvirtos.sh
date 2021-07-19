#!/bin/bash
read -p "Press Enter if script is running as ROOT"
apt install debootstrap squashfs-tools
rm -r live
mkdir live
tmp=$PWD/live

debootstrap buster $tmp
cat << END > $tmp/etc/apt/sources.list
deb http://deb.debian.org/debian/ buster main contrib non-free
deb http://deb.debian.org/debian/ buster-updates main contrib non-free
deb http://deb.debian.org/debian buster-backports main contrib non-free
deb http://security.debian.org/ buster/updates main contrib non-free
END
#run in chroot
cat << END > $tmp/chroot.sh
#!/bin/bash
apt update
apt install qemu-kvm xterm xorg live-boot nano bash-completion alsa-utils pulseaudio
apt install -t buster-backports linux-image-amd64 firmware-misc-nonfree firmware-iwlwifi network-manager

passwd -d root
systemctl disable hwclock.sh
END
chmod +x $tmp/chroot.sh
chroot $tmp /chroot.sh

#script for service
cat << END > $tmp/VMHost.sh
#!/bin/bash
mount -o remount,rw  /lib/live/mount/medium
cd /lib/live/mount/medium/VMs
for x in \$(cat /proc/cmdline); do
  case \$x in
    VM=*)
      VMname=\${x#VM=}
      xinit ./\$VMname.sh --full-screen && poweroff
        ;;
  esac
done
END
chmod +x $tmp/VMHost.sh

#assume local time
echo "0.0 0 0.0
0
LOCAL">$tmp/etc/adjtime

#run it at startup
if ! grep VMHost.sh $tmp/etc/crontab ; then
  echo "@reboot root /VMHost.sh" >> $tmp/etc/crontab
fi

#revert update-initramfs to normal
mv $tmp/usr/sbin/update-initramfs.* $tmp/usr/sbin/update-initramfs

#create squashfs for live filesytem
mksquashfs $tmp filesystem.squashfs -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'

#copy boot files to current directory and set permissive permission
cp $tmp/boot/vmlinuz* vmlinuz
cp $tmp/boot/initrd.img* initrd.img
chmod 777 filesystem.squashfs vmlinuz initrd.img


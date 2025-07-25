#!/bin/bash -e
if [ "$UID" != "0" ]; then
  sudo $0 $@
  exit $?
fi

tmp=$PWD/virtos


if [ ! -d $tmp ]; then
  mkdir -p $tmp
  debootstrap bookworm $tmp
fi

cat << END > $tmp/etc/apt/sources.list
deb https://deb.debian.org/debian bookworm main non-free-firmware
deb https://security.debian.org/debian-security bookworm-security main non-free-firmware
deb https://deb.debian.org/debian bookworm-updates main non-free-firmware
END

#run in chroot
chroot $tmp bash -x << END
#!/bin/bash
apt update
apt install -y linux-image-amd64 pipewire qemu-system-x86
passwd -d root
systemctl disable hwclock.sh
END

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

#create squashfs for live filesytem
mksquashfs $tmp filesystem.squashfs -noappend -wildcards -e 'dev/*' 'media/*' 'mnt/*' 'proc/*' 'lib/live/mount/*' 'run/*' 'sys/*' 'tmp/*'

#copy boot files to current directory and set permissive permission
cp $tmp/boot/vmlinuz* vmlinuz
cp $tmp/boot/initrd.img* initrd.img
chmod 777 filesystem.squashfs vmlinuz initrd.img


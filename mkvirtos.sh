#!/bin/bash
read -p "Press Enter if script is running as ROOT"
apt install debootstrap squashfs-tools
mkdir live
tmp=$PWD/live #$(sudo mktemp -d)

read -p "skip bootstrapping and package installation? [Y/n]" -n 1 yn
case $yn in 
  [Nn]* )
	echo "Erasing live"
	rm -r $tmp/*
	debootstrap bionic $tmp
	cp /etc/apt/sources.list $tmp/etc/apt/sources.list

	#run in chroot
	echo "
	#!/bin/bash
	apt update
	apt install qemu-kvm xterm xorg linux-image-generic live-boot nano bash-completion alsa-base pulseaudio network-manager
	passwd -d root
	systemctl disable hwclock.sh
	">$tmp/chroot.sh
	chmod +x $tmp/chroot.sh
	chroot $tmp /chroot.sh
	;;
  [Yy]* ) ;;
esac

#script for service
echo "
#!/bin/bash
mount -o remount,rw  /lib/live/mount/medium
dhclient
cd /lib/live/mount/medium/VMs
for x in \$(cat /proc/cmdline); do
  case \$x in
    VM=*)
      VMname=\${x#VM=}
      xinit ./\$VMname.sh --full-screen && poweroff
        ;;
  esac
done
"> $tmp/VMHost.sh
chmod +x $tmp/VMHost.sh

#assume local time
echo "0.0 0 0.0
0
LOCAL">$tmp/etc/adjtime

#auto network config
echo "network:
  version: 2
  renderer: NetworkManager" > $tmp/etc/netplan/netman.yaml 

#no kernel messsages because my laptop wont shut up
echo "kernel.printk = 3 4 1 3" > $tmp/etc/sysctl.conf 

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


#!/bin/bash -ex
# steps modified from Arch wiki at 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_tarball_(recommended)
# and https://wiki.archlinux.org/title/installation_guide

if [ ! "$UID" == "0" ]; then
    sudo $0 $@
    exit $?
fi

echo $(losetup | grep /dev/loop0)
[[ "$@" = *"--chroot"* ]] && IS_CHROOT=true || IS_CHROOT=false
echo running in chroot: $IS_CHROOT

#setup package manager
echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
sed -i -e 's/.*ParallelDownloads =.*/ParallelDownloads = 5/g' /etc/pacman.conf
pacman-key --init
pacman-key --populate

#install packages
pacman -Sy
pacman -S --noconfirm --needed mkinitcpio linux
pacman -Syu --noconfirm --needed
pacman -S  --noconfirm --needed base base-devel linux-firmware gparted lshw iperf3 avahi \
    nano bash-completion git htop squashfs-tools net-tools curl wget \
    sudo grub testdisk iotop fuse ntfs-3g \
    make automake autoconf libtool pkg-config openssh screen \
    xf86-video-vesa xf86-video-ati xf86-video-intel xf86-video-amdgpu \
    xf86-video-nouveau xf86-video-fbdev amd-ucode intel-ucode \
    networkmanager dosfstools e2fsprogs plasma-desktop sddm sddm-kcm \
    firefox konsole gnome-disk-utility breeze-gtk dolphin rsync plasma-meta \
    less

cat << END > /etc/tmpfiles.d/live.conf
d /run/live/upper 0755 root root - -
d /run/live/work  0755 root root - -
END

cat << END > /etc/mkinitcpio.live.conf
FILES=(/etc/tmpfiles.d/live.conf)
HOOKS=(base systemd microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems)
COMPRESSION="xz"
END

cat << END > /etc/mkinitcpio.d/linux-live.preset
ALL_config="/etc/mkinitcpio.live.conf"
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux-live.img"
END

cat << END > /etc/fstab.initramfs
/dev/mapper/lower /run/live/lower squashfs defaults 0 0
overlay /sysroot overlay lowerdir=/run/live/lower,upperdir=/run/live/upper,workdir=/run/live/work,x-systemd.requires=/run/live/lower 0 0
END

cat << END > /etc/crypttab.initramfs
lower /run/live/medium/arch_live/filesystem.esquashfs none plain
END

# Build ntfs-3g-system-compression
echo "checking /root"
if [ ! -d "/root/ntfs-3g-system-compression" ]; then
  cd /root/
  git clone https://github.com/ebiggers/ntfs-3g-system-compression.git
  cd ntfs-3g-system-compression
  autoreconf -i
  ./configure
  make install -j$nproc
  ln -s /usr/local/lib/ntfs-3g /usr/lib/ntfs-3g
  cd /
fi

# generate locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
touch /etc/vconsole.conf

#allow user to switch to ramdisk if needed
cat << 'END' > /bin/live-toram
#!/bin/bash -e
if [ ! "$UID" == "0" ]; then
    sudo $0 $@
    exit $?
fi
path=/run/live/medium/arch/filesystem.esquashfs
echo Copying $path to memory.
rsync -a --progress $path /run/live/filesystem
python3 << EOF
import fcntl
loop = open('/dev/loop0')
dest = open('/run/live/filesystem')
fcntl.ioctl(loop,0x4C06,dest.fileno())
loop.close()
dest.close()
EOF
umount $(df $path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6)
END
chmod +x /bin/live-toram

# set default services
systemctl enable NetworkManager sddm sshd 
systemctl set-default graphical
systemctl mask ldconfig systemd-timesyncd
ldconfig -X

#prompt for username
read -p "Type username: " user
useradd -m $user -s /bin/bash -G wheel && passwd $user && sudo -u $user bash -ex << END
kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0 
kwriteconfig6 --file ksplashrc --group Ksplash --key Theme org.kde.breeze.desktop 
kwriteconfig6 --file ksmserverrc --group General --key confirmLogout False
kwriteconfig6 --file PlasmaDiscoverUpdates --group Global --key UseUnattendedUpdates false 
kwriteconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key AutoSuspendAction 0 
kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0 
END

mkdir -p /etc/sddm.conf.d/
cat << END > /etc/sddm.conf.d/kde_settings.conf
[Theme]
Current=breeze
CursorTheme=breeze_cursors
END
#TODO: clock seconds and tap-to-click touchpad

#add user group to sudo and disable warning
cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
%wheel ALL=(ALL:ALL) ALL
END

#remake initcpio
rm -f /boot/*.img
mkinitcpio -p linux-live

#set local time zone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

#if not chroot, find usb path, remount as rw and remount root as ro
path=/
$IS_CHROOT || path=/run/live/medium/arch
$IS_CHROOT || mount -o remount,rw /run/live/medium
$IS_CHROOT || mount -f -o remount,ro /


#create encrypted squashfs
size=$(du -sxB1 /|cut -f1) #measure unencrypted size
size=$(( $size < 4 * 2 ** 30 ? $size : 4 * 2 ** 30 - 1 ))
echo size: $size
systemd-cryptsetup detach newroot ||true #close the encrypted device if its open for some reason
rm -f $path/filesystem.esquashfs.new #delete backing file if it exists
fallocate -l $size $path/filesystem.esquashfs.new #allocate backing file. TODO: this will cause problems if the uncompressed root size is >4GB. this will cause problems on FAT filesystems, which this likely will be, since its an efi partition
systemd-cryptsetup attach newroot $path/filesystem.esquashfs.new none plain #map dm-crypt device to backing file
mksquashfs / /dev/mapper/newroot -comp xz -Xbcj x86 -noappend -wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*' 'var/cache/pacman/pkg' 'var/log' 'usr/share/doc' 'filesystem.esquashfs' 'filesystem.esquashfs.new' #create new squashfs on mapped device
sync
size=$(unsquashfs -s /dev/mapper/newroot | grep -i "filesystem size" | cut -d' ' -f3) #get final compressed size
size=$(( (( $size / 1024 ) + 1 ) * 1024 ))
echo $(($size/1024)) Kbytes
# cryptsetup resize --device-size $size newroot #resize dm-crypt device
sync
systemd-cryptsetup detach newroot #close
truncate -s $size $path/filesystem.esquashfs.new #truncate backing file

#copy kernel and initramfs to live boot drive
cp /boot/initramfs-linux-live.img $path/initramfs-linux-live.img.new
cp /boot/vmlinuz-linux $path/vmlinuz-linux.new

$IS_CHROOT ||read -p "all files updated, press enter to reboot"

#move/overwrite files
mv $path/vmlinuz-linux.new $path/vmlinuz-linux
mv $path/initramfs-linux-live.img.new $path/initramfs-linux-live.img
mv $path/filesystem.esquashfs.new $path/filesystem.esquashfs
sync

#unmount and reboot if not in chroot
$IS_CHROOT || (umount -a || true)
sync
$IS_CHROOT ||echo u > /proc/sysrq-trigger
$IS_CHROOT ||echo b > /proc/sysrq-trigger
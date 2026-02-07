#!/bin/bash -ex
# steps modified from Arch wiki at 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_tarball_(recommended)
# and https://wiki.archlinux.org/title/installation_guide

[ "$UID" == "0" ] || exec sudo $0 $@
[[ "$@" = *"--chroot"* ]] && IS_CHROOT=true || IS_CHROOT=false
echo running in chroot: $IS_CHROOT

#setup package manager
echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
sed -i -e 's/.*ParallelDownloads =.*/ParallelDownloads = 5/g' /etc/pacman.conf
pacman-key --init
pacman-key --populate

#install packages
pacman -Syu --noconfirm
pacman -S  --noconfirm --needed \
    amd-ucode autoconf automake avahi base base-devel \
    bash-completion breeze-gtk curl dolphin dosfstools \
    e2fsprogs efitools efibootmgr firefox fuse git gnome-disk-utility \
    gparted grub htop intel-ucode iotop iperf3 konsole \
    less libtool linux linux-firmware lshw make memtest86+ \
    memtest86+-efi mkinitcpio edk2-shell kate ark \
    mokutil nano net-tools networkmanager ntfs-3g openssh \
    pkg-config plasma-meta rsync screen \
    sddm sddm-kcm squashfs-tools sudo testdisk wget \
    xf86-video-amdgpu xf86-video-ati xf86-video-fbdev \
    xf86-video-intel xf86-video-nouveau xf86-video-vesa \
    usbutils chntpw lsof clamav

#write configs for live boot
cat << END > /etc/fstab.initramfs
/dev/mapper/lower /run/live/lower squashfs loop,ro 0 0
overlay /sysroot overlay lowerdir=/run/live/lower,upperdir=/run/live/upper,workdir=/run/live/work,x-systemd.requires=/run/live/lower 0 0
tmpfs /run tmpfs defaults,size=90% 0 0
END
cat << END > /etc/crypttab.initramfs
lower /run/live/medium/arch_live/filesystem.esquashfs none plain
END
cat << END > /etc/tmpfiles.d/live.conf
d /run/live/upper 0755 root root - -
d /run/live/work  0755 root root - -
END
cat << END > /etc/mkinitcpio.live.conf
MODULES=(ahci ata_piix vfat squashfs loop overlay ahci sd_mod usb_storage uas mmc_block nvme virtio_scsi virtio_blk)
FILES=(/etc/tmpfiles.d/live.conf)
HOOKS=(systemd microcode keyboard sd-vconsole sd-encrypt strip)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=("-19" "-T0")

MODULES_DECOMPRESS="yes"
END
cat << END > /etc/mkinitcpio.d/linux-live.preset
ALL_config="/etc/mkinitcpio.live.conf"
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux-live.img"
END


# generate locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
touch /etc/vconsole.conf

# Build ntfs-3g-system-compression
install -d -o nobody -g nobody -m 777 /aur
cd /aur
if [ ! -d ntfs-3g-system-compression-git ]; then
  sudo -u nobody git clone https://aur.archlinux.org/ntfs-3g-system-compression-git.git
  cd ntfs-3g-system-compression-git
  sudo -u nobody makepkg
  pacman -U --noconfirm ntfs-3g-system-compression-git*.pkg.tar.zst
  cd ..
fi

#allow user to switch to ramdisk if needed
cat << 'END' > /bin/live-toram
#!/bin/bash -e
[ "$UID" == "0" ] || exec sudo $0 $@
echo Copying filesystem to memory.
rsync --copy-links --copy-devices --progress /dev/mapper/lower /run/live/filesystem
python3 << EOF
import fcntl
loop = open('/dev/loop1')
dest = open('/run/live/filesystem')
fcntl.ioctl(loop,0x4C06,dest.fileno())
loop.close()
dest.close()
EOF
cryptsetup close lower
umount /run/live/medium
sync
echo flash drive is now safe to unplug
END
chmod +x /bin/live-toram

# set default services
systemctl enable NetworkManager sddm sshd avahi-daemon
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

#set sddm theme
mkdir -p /etc/sddm.conf.d/
cat << END > /etc/sddm.conf.d/kde_settings.conf
[Theme]
Current=breeze
CursorTheme=breeze_cursors
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
END

#add user group to sudo and disable warning
cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
%wheel ALL=(ALL:ALL) ALL
END

#update clamav database
freshclam

#remake initcpio
rm -f /boot/*.img
mkinitcpio -p linux-live

#set local time zone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

#if not chroot, find usb path, remount as rw and remount root as ro
path=/
if ! $IS_CHROOT; then
  path=/run/live/medium/arch_live
  mount -o remount,rw /run/live/medium
  mount -f -o remount,ro /
fi


#create encrypted squashfs
systemd-cryptsetup detach newroot ||true #close the encrypted device if its open for some reason
rm -f /run/filesystem.esquashfs.new
truncate -s 4G /run/filesystem.esquashfs.new #allocate backing file. TODO: this will cause problems if the uncompressed root size is >4GB. this will cause problems on FAT filesystems, which this likely will be, since its an efi partition
systemd-cryptsetup attach newroot /run/filesystem.esquashfs.new none plain #map dm-crypt device to backing file
mksquashfs / /dev/mapper/newroot -comp zstd -Xcompression-level 19 -b 1M -noappend -wildcards -e 'boot/initramfs*.img boot/vmlinuz*' 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*' 'var/cache/pacman/pkg' 'var/log' 'filesystem.esquashfs' #create new squashfs on mapped device
size=$(unsquashfs -s /dev/mapper/newroot | grep -i "filesystem size" | cut -d' ' -f3) #get final compressed size
size=$(( $size + 1024 ))
systemd-cryptsetup detach newroot #close
truncate -s $size /run/filesystem.esquashfs.new #truncate backing file

#copy kernel and initramfs to live boot drive
cp /boot/initramfs-linux-live.img $path/initramfs-linux-live.img.new
cp /boot/vmlinuz-linux $path/vmlinuz-linux.new
mv /run/filesystem.esquashfs.new $path/filesystem.esquashfs.new
sync

$IS_CHROOT ||read -p "all files updated, press enter to reboot"

#move/overwrite files
mv $path/vmlinuz-linux.new $path/vmlinuz-linux
mv $path/initramfs-linux-live.img.new $path/initramfs-linux-live.img
mv $path/filesystem.esquashfs.new $path/filesystem.esquashfs

$IS_CHROOT || echo u > /proc/sysrq-trigger
$IS_CHROOT || sync
$IS_CHROOT || echo b > /proc/sysrq-trigger
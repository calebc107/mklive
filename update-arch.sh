#!/bin/bash
# steps modified from Arch wiki at 
# https://wiki.archlinux.org/title/Install_Arch_Linux_from_existing_Linux#Method_A:_Using_the_bootstrap_tarball_(recommended)
# and https://wiki.archlinux.org/title/installation_guide
set -e
echo $(losetup | grep /dev/loop0)
[[ "$@" = *"--chroot"* ]] && IS_CHROOT=true || IS_CHROOT=false
echo running in chroot: $IS_CHROOT


echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
sed -i -e 's/.*ParallelDownloads =.*/ParallelDownloads = 5/g' /etc/pacman.conf
pacman-key --init
pacman-key --populate
pacman -Sy
pacman -S --noconfirm --needed mkinitcpio

[ ! -e /etc/mkinitcpio.d/linux.preset.default ] && cp /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux.preset.default
cat << END > /etc/mkinitcpio.d/linux.preset
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux.img"
default_options="-S autodetect -A keyboard,keymap,consolefont,encrypt,live -z xz"
END

cat << END > /etc/initcpio/install/live
build() {
    add_runscript
}
END

cat << 'END' > /etc/initcpio/hooks/live
run_hook(){
    diskuuid=$(getarg live.diskuuid)
    if [ -z "$diskuuid" ]; then
        return 0
    fi
    msg " :: live boot creating dirs"
    mkdir -p /run/live/medium /run/live/lower /run/live/upper /run/live/work
    msg " :: live boot mounting $diskuuid on /run/live/medium"
    while true; do
    mount UUID=$diskuuid /run/live/medium -o ro && break
    sleep 1
    done
    squashfspath=$(getarg live.squashfspath)
    if [ -z "$squashfspath" ]; then
        return 1
    fi
    msg " :: live boot mounting /run/live/medium/$squashfspath on /run/live/lower"
    cryptsetup open --type=plain /run/live/medium/$squashfspath lower
    mount  /dev/mapper/lower /run/live/lower
    msg " :: live boot mounting overlay on /new_root"
    mount -t overlay overlay -olowerdir=/run/live/lower,upperdir=/run/live/upper,workdir=/run/live/work /new_root

    export mount_handler=/bin/true
    
}
END

cat << END > /bin/live-toram
#!/bin/bash
path=\$(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6)
echo Copying \$path to memory.
rsync -a --progress \$path /run/live/filesystem
python3 << EOF
import fcntl
loop = open('/dev/loop0')
dest = open('/run/live/filesystem')
fcntl.ioctl(loop,0x4C06,dest.fileno())
loop.close()
dest.close()
EOF
umount \$(df \$path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6)
END
chmod +x /bin/live-toram

pacman -Syu --noconfirm --needed
pacman -S  --noconfirm --needed base linux linux-firmware gparted lshw iperf3 avahi \
    nano bash-completion git htop squashfs-tools net-tools curl wget \
    sudo grub testdisk iotop fuse ntfs-3g \
    make automake autoconf libtool pkg-config openssh screen \
    xf86-video-vesa xf86-video-ati xf86-video-intel xf86-video-amdgpu \
    xf86-video-nouveau xf86-video-fbdev amd-ucode intel-ucode \
    networkmanager dosfstools e2fsprogs plasma-desktop sddm sddm-kcm \
    firefox konsole gnome-disk-utility breeze-gtk dolphin rsync

systemctl enable NetworkManager sddm
systemctl set-default graphical

#promt user for new username
read -p "Type username: " user
useradd -m $user -G wheel && ( #add user and configure if they dont already exist
    passwd $user
    sudo -u $user lookandfeeltool -a org.kde.breezedark.desktop -platform offscreen
    sudo -u $user kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0 
    sudo -u $user kwriteconfig6 --file ksplashrc --group Ksplash --key Theme org.kde.breeze.desktop 
    sudo -u $user kwriteconfig6 --file PlasmaDiscoverUpdates --group Global --key UseUnattendedUpdates false 
    sudo -u $user kwriteconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key AutoSuspendAction 0 
    sudo -u $user kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0 
    kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Theme --key Current breeze 
    kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Theme --key CursorTheme breeze_cursors 
) || true
#TODO: clock seconds and tap-to-click touchpad

#add whel group to sudo and disable warning
cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
%wheel ALL=(ALL:ALL) ALL
END

#remake initcpio with new config
rm /boot/*.img || true
mkinitcpio -P

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime #set local time zone

find {/usr/share/locale/,/usr/share/help/} -mindepth 1 -maxdepth 1 -not -name "en" -exec rm -r {} \; #remove all locales but en

#if not chroot, find usb path, remount as rw and remount root as ro
path=/
$IS_CHROOT || path=$(dirname $(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6));
$IS_CHROOT || mount -o remount,rw $(df $path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6);
$IS_CHROOT || mount -f -o remount,ro /


#create encrypted squashfs
size=$(du -sxB1 /|cut -f1) #measure unencrypted size
cryptsetup close newroot ||true #close the encrypted device if its open for some reason
rm -f $path/filesystem.esquashfs.new #delete backing file if it exists
fallocate -l $size $path/filesystem.esquashfs.new #allocate backing file. TODO: this will cause problems if the uncompressed root size is >4GB. this will cause problems on FAT filesystems, which this likely will be, since its an efi partition
cryptsetup open --type plain $path/filesystem.esquashfs.new newroot #map dm-crypt device to backing file
mksquashfs / /dev/mapper/newroot -one-file-system -comp xz -Xbcj x86 -noappend -wildcards -e 'var/cache/pacman/pkg' 'var/log' 'usr/share/doc' 'filesystem.esquashfs' 'filesystem.esquashfs.new' #create new squashfs on mapped device
sync
size=$(unsquashfs -s /dev/mapper/newroot | grep -i "filesystem size" | cut -d' ' -f3) #get final compressed size
size=$(( (( $size / 1024 ) + 1 ) * 1024 ))
echo $(($size/1024)) Kbytes
cryptsetup resize --device-size $size newroot #resize dm-crypt device
sync
cryptsetup close newroot #close
truncate -s $size $path/filesystem.esquashfs.new #truncate backing file

#copy kernel and initramfs to live boot drive
cp /boot/initramfs-linux.img $path/initramfs-linux.img.new
cp /boot/vmlinuz-linux $path/vmlinuz-linux.new

$IS_CHROOT ||read -p "all files updated, press enter to reboot"

#move/overwrite files
mv $path/vmlinuz-linux.new $path/vmlinuz-linux
mv $path/initramfs-linux.img.new $path/initramfs-linux.img
mv $path/filesystem.esquashfs.new $path/filesystem.esquashfs
sync

#unmount and reboot if not in chroot
$IS_CHROOT || (umount -a || true)
sync
$IS_CHROOT ||echo u > /proc/sysrq-trigger
$IS_CHROOT ||echo b > /proc/sysrq-trigger




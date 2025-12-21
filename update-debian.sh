#!/bin/bash -ex
if [ ! "$UID" == "0" ]; then
    sudo $0 $@
    exit $?
fi

echo $(losetup | grep /dev/loop0)
[[ "$@" = *"--chroot"* ]] && IS_CHROOT=true || IS_CHROOT=false
echo running in chroot: $IS_CHROOT

#setup package manager
rm -f /etc/apt/sources.list
cat << END > /etc/apt/sources.list.d/debian.sources
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main non-free-firmware contrib non-free
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main non-free-firmware contrib non-free
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
END

#install packages
#export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y linux-image-amd64 network-manager locales
apt -y full-upgrade

# all the firmware in the world 
apt install -y firmware-linux* firmware-atheros \
    firmware-bnx2 firmware-bnx2x firmware-brcm80211 \
    firmware-cavium firmware-cirrus firmware-intel-misc \
    firmware-ipw2x00 firmware-iwlwifi firmware-libertas \
    firmware-linux firmware-linux-nonfree \
    firmware-marvell-prestera firmware-mediatek \
    firmware-misc-nonfree firmware-myricom \
    firmware-netronome firmware-netxen firmware-qcom-soc \
    firmware-realtek firmware-ti-connectivity

#base packages
apt install -y gparted lshw iperf3 avahi-daemon \
    sddm kde-plasma-desktop nano bash-completion git htop squashfs-tools net-tools curl wget \
    live-boot sudo systemd-timesyncd alsa-utils grub2 grub-pc \
    grub-efi-amd64-signed testdisk iotop cryptsetup libfuse-dev ntfs-3g-dev \
    make automake autoconf libtool pkg-config openssh-server screen

apt autoremove
apt autoclean

# Build ntfs-3g-system-compression
echo "checking /root"
if [ ! -d "/root/ntfs-3g-system-compression" ]; then
  cd /root/
  git clone https://github.com/ebiggers/ntfs-3g-system-compression.git
  cd ntfs-3g-system-compression
  autoreconf -i
  ./configure
  make install -j$nproc
  ln -s /usr/local/lib/ntfs-3g /usr/lib/x86_64-linux-gnu/ntfs-3g
  cd /
fi

# generate locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

#allow user to switch to ramdisk if needed
cat << 'END' > /bin/live-toram
#!/bin/bash -e
if [ ! "$UID" == "0" ]; then
    sudo $0 $@
    exit $?
fi
path=$(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6)
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

#restore original update-initramfs behavior
ln -sf /usr/sbin/update-initramfs.orig.initramfs-tools /usr/sbin/update-initramfs

# set default services
systemctl enable NetworkManager sddm ssh 
systemctl set-default graphical
systemctl mask ldconfig systemd-timesyncd
ldconfig -X

#prompt for username
read -p "Type username: " user
useradd -m $user -s /bin/bash -G sudo && passwd $user && sudo -u $user bash -l -ex << END
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


# useradd -m $user -G sudo && passwd $user && sudo -u $user dbus-run-session dconf load /org/gnome/ << END
# [settings-daemon/plugins/power]
# sleep-inactive-ac-timeout=0
# sleep-inactive-battery-timeout=0
# [settings-daemon/plugins/media-keys]
# custom-keybindings=['/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']
# [settings-daemon/plugins/media-keys/custom-keybindings/custom0]
# binding='<Primary><Alt>t'
# command='gnome-terminal'
# name='Terminal'
# [settings-daemon/peripherals/keyboard]
# numlock-state='on'
# [settings-daemon/plugins/media-keys]
# custom-keybindings=['/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']
# [settings-daemon/plugins/media-keys/custom-keybindings/custom0]
# binding='<Primary><Alt>t'
# command='gnome-terminal'
# name='terminal'
# [shell]
# favorite-apps=['firefox-esr.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.Terminal.desktop']
# [nautilus/preferences]
# default-folder-viewer='icon-view'
# [nautilus/icon-view]
# default-zoom-level='standard'
# [desktop/interface]
# clock-show-seconds=true
# gtk-theme='Adwaita-dark'
# [desktop/peripherals/touchpad]
# tap-to-click=true
# END

#add user group to sudo and disable warning
cat << END > /etc/sudoers.d/privacy 
Defaults        lecture = never #Dont nag me
%wheel ALL=(ALL:ALL) ALL
END

#remake initcpio
update-initramfs -ck $(ls -v /lib/modules | tail -n 1)

#set local time zone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

#if not chroot, find usb path, remount as rw and remount root as ro
path=/
$IS_CHROOT || path=$(dirname $(losetup | grep /dev/loop0 | tr -s ' ' | cut -d ' ' -f 6));
$IS_CHROOT || mount -o remount,rw $(df $path | tail -n 1 | tr -s ' ' | cut -d ' ' -f 6);
$IS_CHROOT || mount -f -o remount,ro /


#create squashfs
mksquashfs / $path/filesystem.squashfs.new -comp xz -Xbcj x86 -noappend -wildcards \
    -e 'filesystem.squashfs' 'filesystem.squashfs.new'\
    'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*' 'var/log/*' #create new squashfs on mapped device
sync

#copy kernel and initramfs to live boot drive
cp $(ls -v /boot/initrd* | tail -n 1) $path/initrd.img.new
cp $(ls -v /boot/vmlinuz* | tail -n 1) $path/vmlinuz.new

$IS_CHROOT ||read -p "all files updated, press enter to reboot"

#move/overwrite files
mv $path/vmlinuz.new $path/vmlinuz
mv $path/initrd.img.new $path/initrd.img
mv $path/filesystem.squashfs.new $path/filesystem.squashfs
sync

#unmount and reboot if not in chroot
$IS_CHROOT || (umount -a || true)
sync
$IS_CHROOT ||echo u > /proc/sysrq-trigger
$IS_CHROOT ||echo b > /proc/sysrq-trigger
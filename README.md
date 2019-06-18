# mklive
A collection of scripts for creating custom minimal Debian-based live images

## Usage
mkDebian.sh and mkUbuntu.sh create three files: vmlinuz, initrd.img, and filesystem.squashfs. When booting in grub, you can boot these files by creating a boot entry in your grub.cfg similar to this Ubuntu example:  
```grub
menuentry "Ubuntu" {
	linux		/Ubuntu/vmlinuz ignore_uuid boot=live live-media-path=/Ubuntu
	initrd	/Ubuntu/initrd.img
}
```
live-media-path is relative to the root of the boot drive and is only necessary if you put these files in a subfolder, like in this example.

mkUbuntu has an optional second step, which downloads and installs the GNOME desktop environment as well as some additional software. Once you have booted into the new live Ubuntu installation, log in as root on tty2, and run `/update.sh {path-to-live media}` the path to live media is typically /lib/live/mount/medium/... plus whatever subfolder your installation is in. This update script allows the user to update the system without needing a persistience file.

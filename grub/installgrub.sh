DEV=$1
echo "Installing to $DEV. Press enter to continue."
read
apt install grub-efi-amd64-signed grub-pc
mkdir mnt
sudo mount ${DEV}1 mnt
sudo grub-install --boot-directory ./mnt/boot --target i386-pc $DEV
sudo grub-install --boot-directory ./mnt/boot --target x86_64-efi --uefi-secure-boot --efi-directory --no-nvram ./mnt $DEV
sudo umount ./mnt

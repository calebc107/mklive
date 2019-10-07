DEV=$1
echo "Installing to $DEV. Press enter to continue."
read
mkdir mnt
sudo mount ${DEV}1 mnt
sudo grub-install --boot-directory ./mnt/boot --target i386-pc $DEV
sudo grub-install --boot-directory ./mnt/boot --target x86_64-efi --uefi-secure-boot --efi-directory ./mnt $DEV
cp ./mnt/EFI/boot/grubx64.efi ./mnt/EFI/boot/bootx64.efi
sudo umount ./mnt

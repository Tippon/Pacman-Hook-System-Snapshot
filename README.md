# Pacman Hook System Snapshot

-------------------------

**What does this do?**

This is an automated os snapshot creation tool. It uses btrfs to create bootable snapshots using systemd-boot.

It can also restore said snapshots.

If your system dosen't boot or you somehow managed to break it, you can reboot your computer, boot a snapshot

and restore it.

-------------------------

**Requirements**

I suggest a boot partition with a minimal size of 5GB. The reason behind this is that each snapshot will also

have the boot files (linux kernel, etc.) backed up that it had present at the time.

Your primary partition will have to be btrfs and have your root and home volumes on it.

-------------------------

**Boot partition layout**

```
EFI
installs/active/arch
installs/snapshots
loader/entries
```

-------------------------

**Fstab entries for boot**

```
UUID=boot-uuid          /system-snapshot/boot        vfat            rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro   0 2
/system-snapshot/boot/installs/active/arch           /boot           none            defaults,bind   0 0
```

-------------------------

**Btrfs volume layout**

```
_active/root-arch
_active/home-arch
_snapshots/
```

-------------------------

**Systemd-boot tweaks**

```
bootctl remove
bootctl --path=/system-snapshot/boot install
```

Boot entries need paths included. Example:


```
title Arch Linux
linux /installs/active/arch/vmlinuz-linux
initrd /installs/active/arch/intel-ucode.img
initrd /installs/active/arch/initramfs-linux.img
options root=UUID=root-partition-uuid rootflags=subvol=_active/root-arch resume=UUID=swap-partition-uuid rw
```

-------------------------

**Commands**


Create a snapshot:

```
sudo system-snapshot create
```

Restore a snapshot:

```
sudo system-snapshot restore
```

-------------------------

---
title: Debootstrap a standalone Debian system across multiple partitions
date: 2015-07-07 00:11:42
category: [Storage]
tags: [debootstrap, gdisk, gpt]
---

Having finally finished my MSci Computer Science course at Loughborough University (hoorah!) I am now exploring plausible migration options to move my Debian 7.8 "Wheezy" installation from my Samsung 840 250GB to my new Samsung 850 512GB.

## Intro

The substantial (and controversial\*) transition of the core Debian GNU/Linux init system from the <a href="https://en.wikipedia.org/wiki/UNIX_System_V">System V</a> (default `init` of Debian 7 "Wheezy") to <a href="https://en.wikipedia.org/wiki/Systemd">systemd</a> (default `init` of Debian 8 "Jessie") would potentially favour a complete reinstallation of the system so as to avoid any unforeseen/edge case upgrade issues down the line. 

This post covers how the flexible <a href="https://wiki.debian.org/Debootstrap">debootstrap</a> utility can be used to perform a complete, minimal installation of a Debian 8 "Jessie" system that would traditionally be performed via the Debian installer.
Unlike an external media installation `debootstrap` enables the creation of a Debian system while the host is running. 

Currently official Debian guides covering the `debootstrap` utility are either outdated (https://www.debian.org/releases/lenny/amd64/apds03.html.en ~ Lenny!) or provide very little in terms of reasoning for the operations performed. This post aims to alleviate these two issues in addition to serving as a reference for myself if I decide on the debootstrap solution. 

### Packages

* `gdisk`: 0.8.5-1 
* `debootstrap`: 1.0.48+deb7u2

## Prerequisites

This post pertains to the installation of a comfortably configured (sane and minimal!) standalone Debian 8.1 "Jessie" installation on a _separate_ disk to that of the host machine's root installation. 
Nevertheless, installation of Debian 8 on an external disk can be performed through either a <a href="https://cdimage.debian.org/mirror/cdimage/archive/8.0.0-live/amd64/iso-hybrid/">Live Debian CD/USB</a> or from an existing Debian 7 installation. (Its likely older versions of Debian or any derivatives would work too but I cannot confirm this)

To avoid any accidental misconfiguration adversely affecting my server (e.g. GRUB bootloader issues, incorrect partitioning sizing/layout, etc.) I made the decision to perform all operations in a Debian 7.8 VM that had 2 disks:

```bash
virt-install \
  --name debootstrap_partitions \
  --ram 1024 \
  --virt-type kvm \
  --cpu host \
  --vcpus 1 \
  --disk path=/media/VM/Self\ Study/debootstrap\ partitions/debian-7.2.qcow2,format=qcow2 \
  --import \
  --network=bridge:br1 \
  --disk path=/media/VM/Self\ Study/mdadm\ debootstrap/debootstrapped_install_debian-8.1.qcow2,format=qcow2 
```
Where the `debootstrapped_install_debian-8.1.qcow2` is a 20GiB QCOW2 virtual disk image:
```bash
qemu-img create -f qcow2 /media/VM/Self\ Study/debootstrap\ partitions/debootstrapped_install_debian-8.1.qcow2 20G
```

## Disk partitioning & formatting

In most cases the final system's intended usage will determine its underlying partitioning scheme. To best accommodate for this I have created a <a href="https://en.wikipedia.org/wiki/GUID_Partition_Table">GUID partition table</a> with several entries that can be understood in such a way that it would be easy to either add or remove partitions (based on the user's needs) which ultimately corresponded to the final system's mount points.

### Partition table layout

The layout for my example **20GiB** external disk (`/dev/sdb`) is as follows:

* `bios_boot`: 1MiB  
* `/boot`: 75MiB
* `/`: 3GiB
* `/home`: 3GiB
* `/usr`: 5GiB
* `/var`: 5GiB
* `swap`: ~2GiB (remaining space) 

1. Update the APT package cache and install any outstanding upgrades:
```bash
sudo apt-get update
sudo apt-get upgrade
```

2. Install `gdisk` to create GPT disk partition structures:
```bash
sudo apt-get install gdisk
```

3. Clear any pre-existing GPT (or MBR) structures on the external disk:
```bash
sudo sgdisk --zap-all /dev/sdb
```

4. Create an "empty" (i.e. no partition entries) GPT structure on the external disk:
```bash
sudo sgdisk /dev/sdb
```

5. Create the partitions that will correspond to the final system's mount points. Partitions are aligned on the `gdisk` default recommended 2048 sector boundaries (1 "Mebibyte"); this means that the start sector for every partition must be a multiple of 2048. The aforementioned 7 partitions correspond to the following invocations of `sgdisk` (non-interactive `gdisk`):
```bash
sudo sgdisk --new=1:2048:4097         --typecode=1:EF02 --change-name=1:bios_boot --print /dev/sdb
sudo sgdisk --new=2:6144:159743       --typecode=2:8300 --change-name=2:boot      --print /dev/sdb
sudo sgdisk --new=3:159744:6451199    --typecode=3:8300 --change-name=3:root      --print /dev/sdb
sudo sgdisk --new=4:6451200:16936959  --typecode=4:8300 --change-name=4:home      --print /dev/sdb
sudo sgdisk --new=5:16936960:27422719 --typecode=5:8300 --change-name=5:usr       --print /dev/sdb
sudo sgdisk --new=6:27422720:37908479 --typecode=6:8300 --change-name=6:var       --print /dev/sdb
sudo sgdisk --largest-new=7           --typecode=7:8200 --change-name=7:swap      --print /dev/sdb
```
Make sure to use the KiB/MiB/GiB (*ibibyte) scale _not_ the kB/MB/GB scale when calculating how many sectors each partition is to span across the disk.
I adopted a simple formula for figuring out the last sector of the partition for a given size: `(part_size_in_ibibyte / 512B) + offset - 1`. Where offset is the start of the partition that aligns with the 2048 sector boundary.
The `--typecode` assists (I believe) the OS with determining the underlying partition format. The typecode 8300 corresponds to "Linux filesystem" which in turn corresponds to the partition GUID of: 0FC63DAF-8483-4772-8E79-3D69D8477DE4. A summarised list of GPT typecodes can be listed with: `sudo sgdisk --list-types`. Typecode partition GUID's can be found on Wikipedia <a href="https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs">here.</a>

6. Refresh the kernel's view of the GPT table structure on the external disk:
```bash
echo 1 | sudo tee /sys/block/sdb/device/rescan
```

7. (Optional) Backup the newly created GPT partition table:
```bash
sudo sgdisk --backup=/path/to/backup/debootstrapped_gpt_partitions.bin /dev/sdb
```

8. Format the dedicated `/boot` partition with an `ext2` filesystem:
```bash
sudo mke2fs /dev/sdb2
```

9. Format the other system partitions with your favoured filesystem. For my environment I stuck with the resilient `ext4` filesystem:
```
for i in {3..6}; do
  sudo mkfs.ext4 -q /dev/sdb$i && echo "Partition /dev/sdb$i formatted"
done
``` 

10. Finally format the `swap` partition to prepare it for use:
```bash
sudo mkswap /dev/sdb7
```

## Deboostrap & configure

At this stage we have a finalised GPT partitioning scheme for the external disk with each partition being appropriately formatted in preparation for installing Debian 8.1.

1. Mount the designated root (`/`) partition of the external disk (`/dev/sdb3`) and create the mount points (directories) that link to the other dedicated partitions:
```bash
sudo mkdir /mnt/debootstrap
sudo mount /dev/sdb3 /mnt/debootstrap
sudo mkdir --verbose /mnt/debootstrap/{boot,home,usr,var}
```

2. Mount each of the external disk's partitions to their corresponding directory that was just created. _Double check_ the partitions line up to their desired mount point:
```bash
sudo mount /dev/sdb2 /mnt/debootstrap/boot
sudo mount /dev/sdb4 /mnt/debootstrap/home
sudo mount /dev/sdb5 /mnt/debootstrap/usr
sudo mount /dev/sdb6 /mnt/debootstrap/var
```

3. Install the `debootstrap` utility:
```bash
sudo apt-get install debootstrap
```

4. Invoke `debootstrap` and include some core packages that enable the bootstrapped installation to operate on a standalone basis. Depending on your internet connection, host disk performance, and overall host load this process may take over 5 minutes to complete: 
```bash
sudo debootstrap \
  --include=sudo,openssh-server,locales,linux-image-amd64,grub-pc \
  --arch amd64 stable \
  /mnt/debootstrap \
  http://http.debian.net/debian/
```

5. Mount the host's <a href="https://en.wikipedia.org/wiki/Synthetic_file_system">pseudo filesystems</a> `/proc`, `/sys`, and <a href="https://en.wikipedia.org/wiki/Mount_(Unix)#Bind_mounting">bind mount</a> the host's `/dev` directory within the newly installed Debian 8.1 system. These special mounts are required by GRUB2 for device identification when installing the bootloader to `/dev/sdb`:
```bash
sudo mount --type proc proc /mnt/debootstrap/proc`
sudo mount --type sysfs sysfs /mnt/debootstrap/sys`
sudo mount --bind /dev /mnt/debootstrap/dev`
```

6. While a very core Debian 8.1 system has now been installed across the targeted external disk's partitions several basic configurations that would commonly be automated by the Debian installer are missing (e.g. `/etc/fstab`, `/etc/network/interfaces`). To resolve these issues we need to `chroot` into the new Debian 8.1. installation:
```bash
LANG=C sudo chroot /mnt/debootstrap
```
The environment variable `LANG` is set to eliminate locale warnings when certain applications (i.e. `apt-get`) are ran within the chrooted environment.

    > From this point onward I will assume you are operating inside the `chroot` environment. 
    {: .prompt-warning }

7. To ensure all system partitions are mounted at boot we need to add them in the `/etc/fstab` file. UUID's of partitions can be found by using the `blkid` binary. Feel free to add any other entries to the `/etc/fstab` file for other mounts desired at startup:
```bash
   #
   # Use 'blkid' to print the universally unique identifier for a
   # device; this may be used with UUID= as a more robust way to name devices
   # that works even if disks are added and removed. See fstab(5).
   #
   # <file system>                                 <mount point>   <type>  <options>       <dump>  <pass>
   
   # /boot (/dev/sdb2)
   UUID=368ba92a-4b4e-446c-b5d1-b132131dc286       /boot           ext2    defaults        0       2
   
   # /     (/dev/sdb3)
   UUID=8639b78b-49d8-40c8-9bb1-62b013c478ea       /               ext4    defaults,errors=remount-ro      0       1
   
   # /home  (/dev/sdb4)
   UUID=51ba6674-0b3d-46f9-84d7-670564c5f264       /home           ext4    defaults        0       2
   
   # /usr  (/dev/sdb5)
   UUID=b8b4b210-888e-4862-a2fd-e3c69e5aea92       /usr            ext4    defaults        0       2
   
   # /var  (/dev/sdb6)
   UUID=02331787-02b3-4df1-82fe-2ee90f72a200       /var           ext4    defaults        0       2
   
   # swap  (/dev/sdb7)
   UUID=61b10995-44a6-4e13-8ff0-55fbbe279643       none            swap    defaults        0       0
```
These UUID values were discovered using the `blkid` as follows: 
```bash
sudo blkid /dev/sdb{2..7}
```

8. To configure network interfaces at boot we need to edit the `/etc/network/interfaces` file. For my environment I copied the contents of the host's `/etc/network/interfaces` file into the `chroot`ed Debian 8.1 system:
```bash
   # This file describes the network interfaces available on your system
   # and how to activate them. For more information, see interfaces(5).
   
   # The loopback network interface
   auto lo
   iface lo inet loopback
   
   # The primary network interface
   allow-hotplug eth0
   iface eth0 inet dhcp
```

9. Set the 'root' user account password:
```bash
passwd root
```

10. The Debian installer requires the creation of an unprivileged user account. While this isn't necessary for the operation of our bootstrapped Debian 8.1 system, it is good practice to access the system as an unprivileged user:
```bash
adduser grindon
```

11. Under the assumption the standard user created in the previous is required to execute certain binaries in a privileged state we can add them to the `sudo` group. This step can be skipped if the user is not permitted any form of privilege escalation:
```bash
usermod --append --groups sudo grindon
```

12. We should set the bootstrapped Debian 8.1's hostname so it appears as a separate machine on the network when booted:
```bash
echo "debootstrap-debian" > /etc/hostname`
```

13. Configure the default APT sources and enable the `non-free` and `contrib` repository <a href="https://wiki.debian.org/DebianRepository/Format#Components">components</a>:
```bash
echo 'deb http://http.debian.net/debian stable main non-free contrib' > /etc/apt/sources.list
apt-get update
```

14. Install the GRUB2 bootloader to the external disk the bootstrapped Debian 8.1 system resides upon:
```bash
grub-install /dev/sdb
```

15. Generate the `/boot/grub/grub.cfg` configuration so as to create the boot menu entries for the Debian 8.1 system:
```bash
grub-mkconfig --output /boot/grub/grub.cfg
```

16. Exit the `chroot` environment. If you wish further changes you may make them now, finish up by running the following command to return to the shell session of the local host: 
```bash
exit
```
    > "From this point onward I will assume you are operating inside the host environment."
    {: .prompt-warning }

17. Unmount all pseudo, bind, and traditional filesystems required by the `chroot` environment:
```bash
sudo umount --recursive /mnt/debootstrap
```

## Boot options
The external disk now contains a bootable, standalone Debian 8.1 installation that has system files spread across numerous partitions. At this stage I offer _three_ options for confirming the successful installation of the bootstrapped Debian 8.1 system:

* Update the `/boot/grub/grub.cfg` on the host allowing GRUB2's `os-prober` to detect the Debian installation on /dev/sdb3:
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```
This method doesn't explicitly confirm that GRUB2 and the bootloader have been correctly installed on the external disk. I personally recommend trying out method B. or C. to ensure the system boots _without_ the assistance of another GRUB2 setup.  

* Alter the system's BIOS/UEFI boot order and select the external disk the Debian 8.1 system was `debootstrap`ped as the targeted boot media.

* When accessing the original host's GRUB2 menu (upon boot) enter the GRUB2 console environment by hitting the 'c' key before the first OS option is booted. 
Once in the GRUB2 console environment enter the following commands to chainload the external disk's GRUB2 setup. In my environment the second disk was labelled by GRUB2 as `(hd1)`: 
```bash
set root='(hd1)'
chainloader (hd1)+1
boot
```

## Final Words

Hopefully this post helps illuminate one of the several possibilities the versatile `debootstrap` utility offers when combined with other mounting techniques. Although arguably an edge case scenario for promoting `debootstrap`, I relied upon it for installing a Debian "Wheezy" system (from a Live Debian system via USB) on my Dell Studio 1558 laptop whose screen would no longer output any video of the kind. Thankfully USB boot was set as first priority in its BIOS to boot from USB by allowing me to blindly hit enter once the Live system had booted and then proceed to SSH'ing into the laptop and commence the `debootstrap` process. 

If there is user interest I can write a guide for handling more complex filesystem configurations that may reside on a combination of `mdadm`, `lvm`, and `dm-crypt` utilities. I've recently (successfully) tried out a `mdadm` setup through debootstrap so I see no reason why a combination usage of low-level disk manipulation utilities would not work.

\* I reserve the right to comment my feelings/opinions on *systemd* until I examine and understand its features/capabilities to a greater extent.

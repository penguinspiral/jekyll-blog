---
title: Enabling console access within Libvirt (KVM) hosted Debian images
date: 2014-12-20 10:40:08
categories: [Virtualisation]
tags: [kvm, serial, qemu]
---

Virtualisation plays a crucial part in my own experimentation and understanding of GNU/Linux based systems. On my <a href="http://libvirt.org/">Libvirt</a> VM server ("Octeron") I currently use the VM management interface `virsh` utlity/shell with traditional KVM virtualisation (HVM) as a way of managing/networking/snapshotting my VMs. I consistently use the `virt-install` utility for creating Libvirt managed VMs. 

## Intro

The majority of my VM environments I fire up, experiment in, and eventually tear down are Debian GNU/Linux based (no surprises there...). When I began using `virsh` after moving away from direct QEMU invocations I continued using VNC as it was an easy go-to graphical option that worked out of the box.

The serial console option present in both QEMU (`qemu-system-x86_64`) and, consequently `virsh`, was ultimately preferred for my console orientated experimentations but required further commands/configuration to the corresponding VM. 

This guide covers *three* distinct methods for enabling console access depending upon the situation you find yourself in. Although this guide caters for Debian images, however it may (or may not!) be applicable for other distributions.

### Packages

* `libvirt-bin`: 0.9.12.3-1+deb7u1	
* `virtinst`: 0.600.1-3+deb7u2
* `parted`: 2.3-12
* `gdisk`: 0.8.5-1
* `fdisk`: 0.8.5-1
* `util-linux`: 2.20.1-5.3
* `genisoimage`: 9:1.1.11-2
* `qemu-utils`: 1.1.2+dfsg-6a+deb7u6 (Require kernel config: `CONFIG_BLK_DEV_NBD=m`)

## Console access

Libvirt uses the XML markup language for storing the configurations of VMs, the underlying hypervisor (see "supports" section <a href="https://libvirt.org/drivers.html#hypervisor-drivers">here</a>) will determine the directory where the corresponding VM's XML file is stored. The way in which the serial device is presented to _both_ the VM server and the guest can be configured, however for simplicity this guide uses the Libvirt defaults.

### Network installation

`virsh` provides the functionality to perform a network based boot over a variety of protocols (HTTP, NFS, FTP) by first downloading the kernel (vmlinuz) and initrd pair and then passing them to the VM to boot from. 

Below is a full `virt-install` example for a HTTP network based installation of Debian 7.0 "Wheezy" (<a href="https://www.debian.org/CD/netinst/">"netinst" image</a>) using _only_ the serial console. 

```bash
virt-install
--name test_vm0 \
--ram 1024 \
--cpu host \
--vcpus 2 \
--location  ftp://ftp.debian.org/debian/dists/wheezy/main/installer-amd64/ \
--disk path=/path/to/installation/disk.qcow2,format=qcow2 \
--network=bridge:br1,model=virtio-net-pci \
--graphics none \
--extra-args='console=tty0 console=ttyS0,115200n8 serial'
```

The `--extra-args` line is necessary for accessing the network booted VM over a Libvirt compatible serial connection. Once `virt-install` generates the necessary Libvirt compatible XML the VM will begin booting and you will be _automatically_ connected to the serial console. Serial access is provided between subsequent boots from this point onwards.

Be aware that the the network installation method requires either a locally available Debian repository mirror or an internet connection to access the globally available repositories. Also in this example I have already created the `disk.qcow2` using the `qemu-img` utility.

> Debian 7.0 "Wheezy" will automatically disable (commenting out) the `getty`s that are normally started on `ttys{1..6}` in `/etc/inittab`.  Make sure to enable the `getty` for at least `tty3` if you planned to access the VM through VNC/Spice in the future.
{: .prompt-info }

### ISO installation

A Debian 7.7 "netinst" image has been downloaded (<a href="https://cdimage.debian.org/mirror/cdimage/archive/7.7.0/amd64/jigdo-cd/">Jigdo link</a>) and used for installing a VM from scratch. 

Sadly the Debian 7.7 netinst image isn't configured to provide serial access upon boot. We will need to configure `isolinux.cfg`, `txt.cfg`, and `boot.cat` then finally recreating the ISO image to enable serial functionality. 

This guide is fairly limited in comparison to the graphical method as no initial menu options are presented. Instead we rely on the autoselection of the standard installation option and passing a serial command to that `GRUB2` option in order to access it (credits: <a href="https://lists.debian.org/debian-user/2011/06/msg02544.html">link</a>).

1. Create the mount point to use for accessing the ISO image:
```bash
sudo mkdir /tmp/wheezy-netinst
```

2. Mount the ISO image:
```bash
sudo mount --options loop,ro /path/to/iso/image/debian-7.7.0-amd64-netinst.iso /tmp/wheezy-netinst/
```

3. Due to the read only nature of the <a href="https://en.wikipedia.org/wiki/ISO_9660">ISO9660</a> format we need to create a clone of the ISO image contents and make the necessary changes:
```bash
cp --recursive /tmp/wheezy-netinst/ /path/to/ISO/copy/
```
We copy the entire directory because we need to include the hidden `.disk` directory and its contents - these are crucial for a successful ISO alteration and serial console driven installation.

4. Set write permission for specific <a href="https://wiki.syslinux.org/wiki/index.php?title=ISOLINUX">ISOLINUX</a> files:
```bash
chmod 644 /path/to/ISO/copy/isolinux/wheezy-netinst/{isolinux,txt}.cfg
chmod 644 /path/to/ISO/copy/isolinux/wheezy-netinst/isolinux.bin
```

5. Edit `/path/to/ISO/copy/wheezy-netinst/isolinux.cfg` and increase the "timeout" value:
```bash
/usr/bin/editor  /path/to/ISO/copy/wheezy-netinst/isolinux.cfg 
...
# Set 10 second timeout (1/10s units)
timeout 100
...
```
I'd normally use `sed` here however the directory containing `isolinux.cfg` is readonly and inline (`-i` flag) edits require a temporary file to be created in the targeted file's parent working directory.

6. Edit `/path/to/ISO/copy/wheezy-netinst/txt.cfg` substituting the default VGA option (QEMU does _not_ provision a graphical console when using `graphics = none` setting via `virt-install`) with the serial console:
```bash
/usr/bin/editor  /path/to/ISO/copy/wheezy-netinst/txt.cfg
...
# REMOVE option:
vga=766
...
# APPEND option:
console=ttyS0,115200n8
```
Optional: remove the `quiet` option such that Linux is more verbose during system initialisation.

7. Generate the new ISO image with the serial configuration in place:
```bash
genisoimage -o /path/to/new/ISO/debian-7.7.0-amd64-netinst-serial.iso \
               -r \
               -J \
               -no-emul-boot \
               -boot-load-size 4 \
               -boot-info-table \
               -b isolinux/isolinux.bin \
               -c isolinux/boot.cat \
               /path/to/ISO/copy/wheezy-netinst
```
**genisoimage** flags:
* `-o`: Output ISO location
* `-r`: Generate *rationalized Rock Ridge* directory information, adds POSIX file system semantics (<a href="http://en.wikipedia.org/wiki/Rock_Ridge">more details</a>)
* `-J`: Generate *Joliet* directory information, provides support for Windows-NT or Windows-95 Machines (in the rare case you wish to mount them there!)
* `-no-emul-boot`: Boot image is a "no emulation" image, creating an "El Torito" bootable CD and informing the booting system not to perform any disk emulation
* `-boot-load-size 4`: Specifies the number of "virtual" (512-byte) sectors to load in no-emulation mode
* `-boot-info-table`: Specifies that a 56-byte table with information of the CD-ROM layout will be patched in at offset 8 in the boot file
* `-b`: Specifies the URI of the boot image to be used when making an "El Torito" bootable CD for x86 PCs (URI _must_ be relative to the parent working directory where `genisoimage` is invoked)
* `-c`: Specifies the URI of the boot catalog (`boot.cat`) required for an "El Torito" bootable CD (URI _must_ be relative to the parent working directory where `genisoimage` is invoked)

8. Clean up the modified ISO contents and unmount the original Debian "Wheezy" installer ISO image:
```bash
sudo rm --recursive /path/to/ISO/copy
sudo umount /tmp/debian-wheezy
```

Below is a full `virt-install` example for installing a VM from a locally stored, serial console ready, Debian 7.7 "Wheezy" net installer based ISO image:

```bash
virt-install 
--name test_vm1 \
--ram 1024 \
--cpu host \
--vcpus 2 \
--cdrom /path/to/new/ISO/debian-7.7.0-amd64-netinst-serial.iso \
--disk path=/path/to/installation/disk.qcow2,format=qcow2 \
--network=bridge:br1,model=virtio-net-pci \
--graphics none \
--boot cdrom 
```

Upon installation you will be dropped straight into console (identical to <a href="#network-installation">Network installation</a>). If you removed the `quiet` flag in option 6. you should see the Linux kernel system initalisation logs being displayed shortly after the 10 second mark. Finally you should be presented with the initial "Select Language" installation page.

If for whatever reason you missed the 10 second selection you can still enter console (i.e. `virsh console test_vm1`) and press <kbd>Enter</kbd>. This will automatically select the English language but you will be able to go back and change it if needs be.

### Preinstalled disk image

For this scenario I will consider QCOW2 disk images as the VM's host disk. Another consideration I have taken into account is that multiple partitions are commonly present on Linux systems, in this case I've kept it quite simple: `/boot`, `/home`, and `/`.

> Ensure the targeted QCOW2 disk image is not in use by any process, verify via: `sudo lsof /path/to/installation/disk.qcow2`
{: .prompt-danger }

1. To access the partitions within the QCOW2 disk we must first load the necessary `nbd` (Network Block Device) kernel module:
```bash
sudo modprobe nbd max_part=3
```

2. Assuming `/dev/nbd0` is available mount the QCOW2 disk in a similar way we would mount an ISO image to a loopback device:
```bash
sudo qemu-nbd --connect /dev/nbd0 /path/to/installation/disk.qcow2
```

3. Update the kernel about the partition table layout located on the mounted QCOW2 disk image:
```bash
sudo partprobe /dev/nbd0
```

4. List the partitions off the mounted QCOW2 Disk:
```bash
# MS-DOS partition table
sudo fdisk --list /dev/nbd0
⠀
# GPT partition table
sudo gdisk --list /dev/nbd0
```
If you have labelled your partitions you can use the `blkid` to read the label off of each partition: `sudo blkid /dev/nbd0*`

5. Create the mount point directory for the QCOW2 disk's root partition `/`:
```bash
sudo mkdir /tmp/debian-vm/
```

6. Mount the QCOW2 VM host disk's `/` partition to the newly created mount point directory:
```bash
sudo mount /dev/nbd0p2 /tmp/debian-vm
```

7. Mount the QCOW2 VM host disk's `/boot` partition into the step 6.'s mounted root partition's relative `boot` directory:
```bash
sudo mount /dev/nbd0p1 /tmp/debian-vm/boot
```

8. Change the apparent root directory for the current interactive shell into step 5.'s mounted root partition:
```bash
sudo chroot /tmp/debian-vm/
```
We do this to avoid accidentally editing the running host's configuration files. 

9. Edit `/etc/inittab` and ensure that a `getty` is listening on `ttyS0` (serial TTY) for the standard interactive SysVinit runlevels: 
```bash
T0:23:respawn:/sbin/getty -L ttyS0 115200 vt102
```

10. Edit '/etc/default/grub2.cfg' to configure GRUB2 for access via the serial console:
```bash
# Affects non-recovery Linux kernel(s) only
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8 serial"
GRUB_TERMINAL=serial
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1"
```

11. Edit `/boot/grub/grub.cfg` to enable a _single_ kernel to redirect its initialisation output to the serial console:
```bash
...
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial`
set timeout=20
### END /etc/grub.d/00_header ###
...
linux	/vmlinuz-3.2.0-4-amd64 root=UUID=a30f22a5-b4b4-46ee-8bc3-ca39ef972be6 ro text <b>console=tty0 console=ttyS0,115200n8 serial</b>` # 1st listed _non_-recovery kernel
```
This step would _typically_ be done via the `update-grub2` command as per the `grub.cfg` file's header recommendation.


12. Exit the chroot: 
```bash
exit
```

13. Unmount the 2 QCOW2 disk partitions:
```bash
sudo umount --verbose --recursive /tmp/debian-vm/
```

14. Disconnect the QCOW2 VM disk image from the `nbd0` block device node:
```bash
sudo qemu-nbd --disconnect /dev/nbd0
```

15. Start the VM:
```bash
virsh start existing-vm
```

16. Access the VM via the serial console:
```bash
virsh console existing-vm
```

17. Inside the VM apply the GRUB2 configuration across all _non_-recovery kernels:
```bash
sudo update-grub2
```

#### Demo

Configuring the <a href="#preinstalled-disk-image">preinstalled disk image</a> is a fairly involved process in comparison to the other two installation options. As a result I've recorded a terminal session which follows this section to completion to illustrate the expected feedback from such commands.

<script type="text/javascript" src="https://asciinema.org/a/15953.js" id="asciicast-15953" async></script>

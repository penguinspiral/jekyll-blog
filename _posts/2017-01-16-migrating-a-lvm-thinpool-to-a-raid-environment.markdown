---
title: Migrating LVM thin {pools,volumes,snapshots} to a software RAID environment
date: '2017-01-16 06:31:44'
categories: [Storage]
tags: [lvm, mdadm, libvirt]
---

As part of Octeron's (my VM server) migration from Debian GNU/Linux "Wheezy" 7.9 to Debian GNU/Linux "Jessie" 8.2 I analysed and refined my typical virtual machine (VM) lifecycle workflow (i.e. creation/importing/cloning, usage, snapshot(s), exporting, deletion) in an effort to improve VM flexibility, maintainability, and resilience. By starting anew I was able to examine the various limitations imposed by my previous Virtual Machine Management (VMM) environment and consider viable alternatives that would better suit my needs.

## Intro

My original Debian GNU/Linux "Wheezy" 7.9 deployment employed the versatile QCOW2 virtual disk image format for housing all my VMs. The virtual disk images themselves resided upon a performance tuned Ext4 file system (writeback caching, no barriers, etc.). This Ext4 file system was in turn situated upon a LVM based Logical Volume which, in turn, resided entirely within a large GPT based partition sat atop a 250GB Samsung 840 SSD. VMs that didn't require SSD speeds and/or had notably larger space requirements would be stored on the WD Red 3TB HDD. 

While I received the numerous benefits QCOW2 offered such as: saving system state, internal snapshots, utilising backing disks for space efficient clones of desired VMs (a.k.a external snapshots), and many others I found that my original Ext4 + LVM deployment wasn't suited for my planned growth (i.e. adding SSDs) with Octeron. While it was feasible to extend the Volume Group across newly added SSDs, grow the Logical Volume, and ultimately expand the performance focused Ext4 filesystem, it didn't provide any resilience against disk failures or any potential performance increases. Instead these benefits would come from employing software/hardware RAID or altering LVM to perform striping/mirroring on the existing deployment.

One big "irk" however that drove me to investigating, and ultimately deploying LVM Thin pools/volumes/snapshots, was a particular external snapshot chaining limitation I found from using QCOW2 virtual disk images. Kashyap Chamarthy, an OSS developer focusing on improving the Virtualisation stack within Linux for Red Hat, explains the concept of an "External Snapshot" from the QCOW2 disk format perspective (<a href="http://kashyapc.com/2012/09/14/externaland-live-snapshots-with-libvirt/">source</a>): 

> _"external snapshots are a type of snapshots where, there’s a base image (which is the original disk image), and then its difference/delta (aka, the snapshot image) is stored in a new QCOW2 file. Once the snapshot is taken, the original disk image will be in a ‘read-only’ state, which can be used as backing file for other guests."_
 
In the past I would have had a "minimal" installation (i.e. no options chosen at the `tasksel` prompt) of a Debian VM serve as a "base image" as a means of creating space efficient (a.k.a. "thin provisioned") clones for various Debian driven VM environments. The main issue I encountered was that over time the base image would become out of date and consequently utilising this _stale_ image for new VMs would require updating the APT cache in tandem with an upgrade of an ever growing set of outdated packages within _each_ thinly provisioned VM. 
A combination of old VM environments that utilised an out-of-date base image as their "backing disk" and my own futile attempts in regularly creating a new up-to-date Debian base image (by performing a "full-fat" cloning of the original base disk and updating it) for future VMs to use as a backing disk resulted in a messy environment that would not be sustainable nor scalable for future larger scale experimentations.

Ultimately I wanted a space efficient solution that allowed a VM which would served as a base disk to to keep itself updated without it adversely affecting other "snapshot" derived VMs. In addition to this, I wanted to be able to employ recursive snapshots when necessary in a manner similar to chaining external snapshots with QCOW2 images. Unlike chained QCOW2 images however, I desired the ability to remove a virtual disk image from an arbitrarily long chain without it rendering all "child" snapshots (from the removed snapshot's perspective) nonoperational.

I found that the capabilities offered by LVM Thin pools/volumes/snapshots fulfilled these requirements and therefore sought about configuring my VM server (Octeron) to accommodate this storage backend. Nevertheless my investigation and ultimate deployment of a LVM Thin storage backend revealed some additional complexities and restrictions when compared to the traditional QCOW2 approach. I've outlined these disadvatages in a dedicated section at the end of this guide so as to provide a complete picture of its usage in a virtualisisation storage role and whether it is suitable in your environment.   

Given that the LVM Thin "environment" (i.e. pools, volumes, and snapshots) was being considered as a replacement for my limited QCOW2 workflow on Octeron I decided to simulate the addition of future SSDs within a Debian GNU/Linux "Jessie" VM. This guide therefore serves as a walkthrough for those wishing to rebase their LVM Thin environment atop a software RAID (`mdadm`) storage backend. 
Please note that while this guide provides the example of a software RAID environment being the migration target, this need not be the restoration endpoint. The exportation process permits the restoration on to various storage backends. 

> For brevity sake this guide does not demonstrate the necessary creation steps for LVM Thin pools/volumes/snapshots. Such guides are in abundance on the web (e.g. <a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Logical_Volume_Manager_Administration/thinly_provisioned_volume_creation.html">here</a>, <a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Logical_Volume_Manager_Administration/thinly_provisioned_snapshot_creation.html">here</a>, and <a href="https://wiki.gentoo.org/wiki/LVM#Thin_provisioning">here</a>) as well as being outlined in sufficient depth within the respective `man` pages (e.g. `man lvmthin`). 
{: .prompt-info }

> A bug was discovered when attempting to import a previously exported LVM Thin environment on top of a `mdadm` based, software RAID 5 environment. This appears to only affect the Debian GNU/Linux "Jessie" kernel (`linux-image-3.16.0-4-amd64` -> `3.16.7-ckt11-1+deb8u3`) but results in the inability to write to any of the imported LVM Thin environment. This issue does not appear to affect the Debian GNU/Linux "Stretch" kernel (`linux-image-4.2.0-1-amd64` -> `4.2.6-3`) and above however.
{: .prompt-danger }

### Packages

* `lvm2`: 2.02.111-2.2
* `thin-provisioning-tools`: 0.3.2-1
* `dmsetup`: 2:1.02.09-2.2
* `mdadm`: 3.3.2-5
* `kpartx`: 0.5.0-6+deb8u2
* `gdisk`: 0.8.10-2
* `linux-image-4.2.0-1-amd64`: 4.2.6-3

## LVM Thin environment

A brief summary of each "thin provisioning" component that makes up LVM's Thin provisioning offering is outlined here so as to give the reader a high level understanding of each component and how they interact with one another. A special mention should be given to the Gentoo Wiki writers/contributors from which I have derived (and directly copied in some cases) their succinctly summarised meanings of the components. 

### LVM Thin _Pool_

> _"A special type of logical volume, which itself can host logical volumes."_ (<a href="https://wiki.gentoo.org/wiki/LVM#Thin_provisioning">Gentoo Wiki</a>). 

Upon creation it dictates the total number of <a href="https://en.wikipedia.org/wiki/Extent_(file_systems)">extents</a> that can be consumed by thin _volumes_/_snapshots_. 
If all available extents in a LVM pool are consumed then: 
> "_any process that would cause the thin pool to allocate more (unavailable) extents will be stuck in 'killable sleep' state until either the thin pool is extended or the process receives SIGKILL_" (<a href="https://wiki.gentoo.org/wiki/LVM#Thin_provisioning">Gentoo Wiki</a>)

> A thin _pool_ can be grown (online/offline) but not shrunk. (<a href="https://www.redhat.com/archives/linux-lvm/2014-March/msg00020.html">source</a>)
{: .prompt-warning }

### LVM Thin _Volume_

> _"Thin volumes are to block devices what sparse files are to file systems"_ (<a href="https://wiki.gentoo.org/wiki/LVM#Thin_provisioning">Gentoo Wiki</a>).

Analogous to the behavior of <a href="https://en.wikipedia.org/wiki/Sparse_file">sparse files</a> in the sense that blocks (extents in this case) are assigned when requested as opposed to being preallocated upon creation; thin _volumes_ consequently adhere to the "over-committed" storage principle. This inherent characteristic means that thin _volumes_ can be allocated more extents than what is presently available in thin _pool_. (<a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Logical_Volume_Manager_Administration/lv_overview.html#thinprovisioned_volumes">source</a>)

> A thin _volume_ can be grown (online/offline) and shrunk (online/offline) as desired. (<a href="https://wiki.gentoo.org/wiki/LVM#Reducing_a_thin_logical_volume">source</a>)
{: .prompt-info }

### LVM Thin _Snapshot_

Operates on the traditional COW (Copy-On-Write) behaviour that is similar to traditional LVM writeable snapshots with the additional functionality of arbitrarily deep chaining of thin _snapshots_. If the "base" thin _volume_ (origin) is removed from the thin _pool_ the snapshot will automatically transition to a standalone thin _volume_. (<a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Logical_Volume_Manager_Administration/lv_overview.html#thinly-provisioned_snapshot_volumes">source</a>)

> A thin _snapshot_ is not explicitly assigned a size upon creation (as is the case with traditional/standard LVM snapshots) as by design it will always be the same size as the thin _volume_ it is snapshotting. (<a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Logical_Volume_Manager_Administration/lv_overview.html#thinly-provisioned_snapshot_volumes">source</a>)
{: .prompt-warning }

For those wishing to learn more about LVM and LVM's Thin provisioning components I recommend reading the freely available RHEL 7 LVM administration documentation (<a href="https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Logical_Volume_Manager_Administration/LV.html" >here</a>) in addition to the comprehensive Gentoo Wiki (<a href="https://wiki.gentoo.org/wiki/LVM">here</a>).

## Disk array configuration

For the purpose of this guide the disk layout utilised inside the Debian GNU/Linux "Jessie" VM roughly mimics that of the next "step" in my planned storage expansion within Octeron.  

### Virtual block devices

* 4 x 20GiB virtual disks: Attached to a Debian GNU/Linux Jessie VM via the paravirtualised *virtio* bus so as to leverage the increased I/O performance and reduced CPU overhead by the KVM hypervisor. 

    * The first enumerated virtual disk `/dev/vda` contains a 10GiB partition (`/dev/vda3`) where an example LVM "Thin" environment has been configured. This simple environment should be considered as the start point for this guide.

    * The second enumerated virtual disk `/dev/vdb` mimics Octeron's 3TB WD Red drive and has been simplified to that of a single Ext4 formatted partition. This particular mount; `/mount/storage`, will store the necessary LVM Thin environment data required for eventual restoration on the targeted software RAID environment.

    * The remaining 2 x virtual disks: `/dev/vd{c,d}` are to be considered minified, virtual equivalents of the additional SSDs planned for eventual inclusion within Octeron. They share the same GPT table as the first enumerated virtual disk `/dev/vda` (using `sgdisk` for backing up and restoring GPT partition tables).

### LVM Thin environment

* The LVM Thin environment, outlined in more detail below, contains: 

    * 1 x LVM Thin _pool_
    * 3 x LVM Thin _volumes_ 
    * 1 x LVM Thin _snapshot_

* The LVM Thin _pool_ consists of three distinct LVM Volumes: 

    1. A Thin pool `data` volume `/dev/mapper/vms-thinpool_data` that stores all "standard" data for both Thin _volumes_ and Thin _snapshots_. 
    2. A Thin pool `metadata` volume `/dev/mapper/vms-thinpool_tmeta` that keeps track of block changes between Thin _volumes_ and their respective derivative Thin _snapshots_. 

        * The more "variance" (i.e. block changes) there is between a Thin _volume_ and its subsequent Thin _snapshot_(s) the more metadata information is required for tracking these aforementioned variances.

    3. A "spare" Thin pool `metadata` volume (no `/dev` node as the spare metadata volume is not 'activated' and subsequently exposed in the same manner as a typical LVM volume) that is automatically created (unless explicitly specified otherwise) during Thin Pool creation. It provides the means for recovering a Thin pool should the main Thin pool's _metadata_ volume become corrupted/damaged.

* User defined LVM Thin _volume_ & _snapshots_ :

   * 3 x Thin _volumes_ `/dev/mapper/vms-thinvol{1,2,3}`

   * 1 x Thin _snapshot_ `/dev/mapper/vms-thinvol1_snap0` (of Thin _volume_ `vms-thinvol1`).

       * Each Thin _volume_ and Thin _snapshot_ contains a GPT partition table which in turn contains a single Ext4 formatted partition. Debian GNU/Linux exposes such a structure as: `/dev/mapper/vms-thinvol{1,2,3}p1` and `/dev/mapper/vms-thinvol1snap0p1` respectively. 


In an effort to help illustrate the aforementioned environment I've included the console output (below) for the block device listings (`lsblk`) and the Logical Volume setup (`lvs`).
```bash
lsblk
NAME                           MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
sr0                             11:0    1 1024M  0 rom   
vda                            254:0    0   20G  0 disk  
|-vda1                         254:1    0    1M  0 part  
|-vda2                         254:2    0   10G  0 part  
| `-md0                          9:0    0   10G  0 raid1 /
`-vda3                         254:3    0   10G  0 part  
  |-vms-thinpool_tmeta         252:0    0    8M  0 lvm   
  | `-vms-thinpool-tpool       252:2    0    8G  0 lvm   
  |   |-vms-thinpool           252:3    0    8G  0 lvm   
  |   |-vms-thinvol1           252:4    0    2G  0 lvm   
  |   | `-vms-thinvol1p1       252:9    0    2G  0 part  
  |   |-vms-thinvol2           252:5    0    2G  0 lvm   
  |   | `-vms-thinvol2p1       252:8    0    2G  0 part  
  |   |-vms-thinvol3           252:6    0    2G  0 lvm   
  |   | `-vms-thinvol3p1       252:7    0    2G  0 part  
  |   |-vms-thinpool-tpool1    252:10   0    2G  0 part  
  |   `-vms-thinvol1_snap0     252:12   0    2G  0 lvm   
  |     `-vms-thinvol1_snap0p1 252:13   0    2G  0 part  
  `-vms-thinpool_tdata         252:1    0    8G  0 lvm   
    |-vms-thinpool-tpool       252:2    0    8G  0 lvm   
    | |-vms-thinpool           252:3    0    8G  0 lvm   
    | |-vms-thinvol1           252:4    0    2G  0 lvm   
    | | `-vms-thinvol1p1       252:9    0    2G  0 part  
    | |-vms-thinvol2           252:5    0    2G  0 lvm   
    | | `-vms-thinvol2p1       252:8    0    2G  0 part  
    | |-vms-thinvol3           252:6    0    2G  0 lvm   
    | | `-vms-thinvol3p1       252:7    0    2G  0 part  
    | |-vms-thinpool-tpool1    252:10   0    2G  0 part  
    | `-vms-thinvol1_snap0     252:12   0    2G  0 lvm   
    |   `-vms-thinvol1_snap0p1 252:13   0    2G  0 part  
    `-vms-thinpool_tdata1      252:11   0    2G  0 part
vdb                            254:16   0   20G  0 disk  
`-vdb1                         254:17   0   20G  0 part  /mnt/storage
vdc                            254:32   0   20G  0 disk  
|-vdc1                         254:33   0    1M  0 part  
|-vdc2                         254:34   0   10G  0 part  
| `-md0                          9:0    0   10G  0 raid1 /
`-vdc3                         254:35   0   10G  0 part  
vdd                            254:48   0   20G  0 disk  
|-vdd1                         254:49   0    1M  0 part  
|-vdd2                         254:50   0   10G  0 part  
| `-md0                          9:0    0   10G  0 raid1 /
`-vdd3                         254:51   0   10G  0 part  
```
{: .nolineno }

```bash
sudo lvs --all --options lv_name,vg_name,attr,lv_size,data_percent
  LV               VG   Attr       LSize Data% 
  [lvol0_pmspare]  vms  ewi------- 8.00m       
  thinpool         vms  twi-aotz-- 7.99g 6.10  
  [thinpool_tdata] vms  Twi-ao---- 7.99g       
  [thinpool_tmeta] vms  ewi-ao---- 8.00m       
  thinvol1         vms  Vwi-aotz-- 2.00g 7.35  
  thinvol1_snap0   vms  Vwi-aotz-- 2.00g 7.39  
  thinvol2         vms  Vwi-aotz-- 2.00g 8.17  
  thinvol3         vms  Vwi-aotz-- 2.00g 8.07  
```
{: .nolineno }

## Exporting the LVM Thin environment

As mentioned earlier this particular step of the guide aims to be agnostic such that the exported LVM Thin environment can be migrated on a wide range of storage targets. 
> Despite having personally tested the following steps for successfully exporting a LVM Thin environment I _strongly_ recommended backing up any data from the LVM Thin volumes and Thin snapshots before proceeding. 
{: .prompt-warning }

1. Unmount any active (i.e. mounted) partitions that reside on LVM Thin _volume(s)_ or Thin _snapshot(s)_:
```bash
sudo umount /dev/mapper/vms-thinvol{1..3}p1
sudo umount /dev/mapper/vms-thinvol1_snap0p1
```
     {: .nolineno }

2. Remove any partition derived device mappings from both the LVM Thin _volume(s)_ and Thin _snapshot(s)_:
```bash
sudo kpartx -d /dev/mapper/vms-thinvol1
sudo kpartx -d /dev/mapper/vms-thinvol2
sudo kpartx -d /dev/mapper/vms-thinvol3
sudo kpartx -d /dev/mapper/vms-thinvol1_snap0
```
    {: .nolineno }
> You can skip this section if you did _not_ utilise GPT (or MBR) within your LVM Thin _volume(s)_ or Thin _snapshot(s)_.  
    {: .prompt-info }

3. Temporarily deactivate all Thin _volume(s)_ and Thin _snapshot(s)_. While this removes the availability of the Logical Volume (LV) for use (e.g. `/dev/mapper/vms-thinvol1` is no longer exposed) it does ensure that any I/O to the Logical Volume (LV) syncs fully: 
```bash
sudo lvchange --activate n vms/thinvol1
sudo lvchange --activate n vms/thinvol2
sudo lvchange --activate n vms/thinvol3
sudo lvchange --activate n vms/thinvol1_snap0
```
    {: .nolineno }
> If you were to attempt to deactivate the LVM Thin _volume_ or Thin _snapshot_ during any form of I/O the `lvchange` command would block until the external operation had completed. Therefore the purpose of this step is to ensure all read/write operations have completed before exporting the LVM Thin _volume(s)_/_snapshot(s)_. 
    {: .prompt-info }

4. Re-activate all Thin _volume(s)_ and Thin _snapshot(s)_ ensuring to enable them in a readonly mode to prevent any alterations during the exporting process:
```bash
sudo lvchange --activate y --permission r vms/thinvol1
sudo lvchange --activate y --permission r vms/thinvol2
sudo lvchange --activate y --permission r vms/thinvol3
sudo lvchange --activate y --permission r vms/thinvol1_snap0
```
    {: .nolineno }
> You can confirm that the LVM Thin _volume(s)_ and Thin _snapshot(s)_ are in a readonly state by examining the `Attr` column in `lvs`; if it is 'r' then the Logical Volume (LV) is exposed readonly.
    {: .prompt-info }

5. Perform a `sparse` block copy of all LVM Thin _volume(s)_ and Thin _snapshot(s)_ saving the resulting disk images to the external storage location: `/mnt/storage`. To further save space I used `gzip` to compress the LVM Thin _volume(s)_ and Thin _snapshot(s)_ before saving them:
```bash
sudo dd if=/dev/mapper/vms-thinvol1 bs=4M conv=sparse | gzip --stdout --best > /mnt/storage/images/vms-thinvol1.raw.gz
sudo dd if=/dev/mapper/vms-thinvol2 bs=4M conv=sparse | gzip --stdout --best > /mnt/storage/images/vms-thinvol2.raw.gz
sudo dd if=/dev/mapper/vms-thinvol3 bs=4M conv=sparse | gzip --stdout --best > /mnt/storage/images/vms-thinvol3.raw.gz
sudo dd if=/dev/mapper/vms-thinvol1_snap0 bs=4M conv=sparse | gzip --stdout --best > /mnt/storage/images/vms-thinvol1_snap0.raw.gz
```
    {: .nolineno }

6. Backup the LVM Volume Group (VG) "descriptor area" (i.e. metadata pertaining to the VG and consequently the Logical Volumes sat atop) containing the "Thin" environment. This particular VG metadata file will be required during the import phase of the LVM "Thin" environment at the end of this guide.  
```bash
sudo vgcfgbackup --verbose --file /mnt/storage/metadata/vms_backup vms
```
    {: .nolineno }

7. Export the Thin Pool metadata that keeps track of block changes between Thin _volume(s)_ and their respective Thin _snapshot(s)_:
```bash
sudo thin_dump /dev/mapper/vms-thinpool_tmeta > /mnt/storage/metadata/vms-thinpool_tmeta.xml
```
    {: .nolineno }

8. Deactivate all LVM Logical Volume (LV) components within the LVM "Thin" environment contained within a given Volume Group (VG). Assuming that none of the LVs are in use we can have all LVs including the VG deactivated in a single command:
```bash
sudo vgchange --activate n vms
```
    {: .nolineno }

9. Proceed to remove the recently deactivated Volume Group (VG). Respond with 'y' when prompted about the volume dependencies within the "Thin" environment.
```bash
sudo vgremove vms
```
    {: .nolineno }

10. Finally remove the Physical Volume (PV) the VG and consequently the LVM "Thin" environment had previously been built upon:
```bash
sudo pvremove /dev/vda3
```
    {: .nolineno }

At this stage we have removed all LVM layout configuration. These destructive alterations should be evident when compared to the initial LVM deployment:
```bash
lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
sr0      11:0    1 1024M  0 rom   
vda     254:0    0   20G  0 disk  
|-vda1  254:1    0    1M  0 part  
|-vda2  254:2    0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vda3  254:3    0   10G  0 part  
vdb     254:16   0   20G  0 disk  
`-vdb1  254:17   0   20G  0 part  /mnt/storage
vdc     254:32   0   20G  0 disk  
|-vdc1  254:33   0    1M  0 part  
|-vdc2  254:34   0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vdc3  254:35   0   10G  0 part  
vdd     254:48   0   20G  0 disk  
|-vdd1  254:49   0    1M  0 part  
|-vdd2  254:50   0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vdd3  254:51   0   10G  0 part  
```
{: .nolineno }

```bash
sudo lvs --all --options lv_name,vg_name,attr,lv_size,data_percent
No volume groups found
```
{: .nolineno }

## Configuring RAID

Now that we have successfully exported the necessary configuration/metadata files in addition to the actual data content of the LVM Thin environment we can proceed to establish the software RAID target. For this particular test environment I will create a software RAID 5 setup across the 3 virtual SSD disks (`vda`,`vdc`, and `vdd`) on their *third* partition respectively.

1. Create the software RAID 5 array across the third partition on each of three SSD virtual disks:
```bash
sudo mdadm --create /dev/md1 --level=5 --raid-devices=3 /dev/vda3 /dev/vdc3 /dev/vdd3
```
    {: .nolineno }

2. Monitor the progress of RAID 5 array setup while it is constructed:
```bash
cat /proc/mdstat
Personalities : [raid1] [raid6] [raid5] [raid4] 
md1 : active raid5 vdd3[3] vdc3[1] vda3[0]
      20947968 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [UU_]
      [=================>...]  recovery = 88.1% (9237496/10473984) finish=0.3min speed=57908K/sec
...
[3940703.593615] md: md1: recovery done.
```
    {: .nolineno }
> The software RAID 5 array (`/dev/md1`) can be interacted with during the initial build however the responsiveness and overall I/O throughput will be notably less due to the competing creation process. 
    {: .prompt-info }

3. Examine the newly created software RAID 5 array to ensure that the Linux kernel has detected the software RAID 5 target (`/dev/md1`) across the correct disks (`vda`,`vdc`, and `vdd`) and the correct partitions:
```bash
lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
sr0      11:0    1 1024M  0 rom   
vda     254:0    0   20G  0 disk  
|-vda1  254:1    0    1M  0 part  
|-vda2  254:2    0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vda3  254:3    0   10G  0 part  
  `-md1   9:1    0   20G  0 raid5 
vdb     254:16   0   20G  0 disk  
`-vdb1  254:17   0   20G  0 part  /mnt/storage
vdc     254:32   0   20G  0 disk  
|-vdc1  254:33   0    1M  0 part  
|-vdc2  254:34   0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vdc3  254:35   0   10G  0 part  
  `-md1   9:1    0   20G  0 raid5 
vdd     254:48   0   20G  0 disk  
|-vdd1  254:49   0    1M  0 part  
|-vdd2  254:50   0   10G  0 part  
| `-md0   9:0    0   10G  0 raid1 /
`-vdd3  254:51   0   10G  0 part  
  `-md1   9:1    0   20G  0 raid5
```
    {: .nolineno }
```bash
sudo blkid /dev/vd{a,c,d}3 | awk '{print $2}'
UUID="88ed62e0-052b-d369-85a5-e78af70a9bed"
UUID="88ed62e0-052b-d369-85a5-e78af70a9bed"
UUID="88ed62e0-052b-d369-85a5-e78af70a9bed"
```
    {: .nolineno }

4. Append the software RAID 5 target details to the system wide `mdadm` configuration file, `/etc/mdadm/mdadm.conf`, for enumeration once the root filesystem (located on RAID 1 target `/dev/md0`) has been mounted: 
```bash
sudo mdadm --detail --scan /dev/md1 | sudo tee --append /etc/mdadm/mdadm.conf
```
    {: .nolineno }

## Restoring the LVM Thin environment

With a fully initialised software RAID 5 target we can proceed to restore the LVM Thin environment. I'd like to reiterate at this stage that the target migration storage backend does not have to be a software RAID setup. The motivation for a software RAID target for this guide was for understanding the steps necessary for my storage expansion plans on Octeron.

1. Create a new Physical Volume (PV) on the *multiple disk* RAID 5 block device node (`/dev/md1`):
```bash
sudo pvcreate /dev/md1
```
    {: .nolineno }

2. Obtain the UUID of the newly created Physical Volume (PV). The new PV's UUID is required during the import process of the Volume Group (VG) metadata configuration file:
```bash
sudo pvdisplay /dev/md1 | grep UUID
```
    {: .nolineno }

3. With your favourite text editor alter the Volume Group (VG) metadata configuration file, `/mnt/storage/metadata/vms_backup`, and update both the `id` and `device` values to reflect the new created PV: 
```bash
pv0 {
        id = "$UUID_OF_NEW_PV"
        device = "/dev/md1"
```
    {: .nolineno }

4. Restore the Physical Volume (PV) related metadata configuration from the exported Volume Group (VG) metadata configuration file using the newly created PV UUID:
```bash
sudo pvcreate --uuid $UUID_OF_NEW_PV \
                 --restorefile /mnt/storage/metadata/vms_backup \
                 /dev/md1
```
    {: .nolineno }

5. Check the Physical Volume (PV) LVM metadata to ensure that the imported metadata is consistent:
```bash
sudo pvck /dev/md1
Scanning /dev/md1
Found label on /dev/md1, sector 1, type=LVM2 001
Found text metadata area: offset=4096, size=1044480
```
    {: .nolineno }

6. Restore the remaining Volume Group (VG) and Logical Volume (LV) metadata information from the exported VG metadata configuration file:
```bash
sudo vgcfgrestore --file /mnt/storage/metadata/vms_backup 
                      --force vms
```
    {: .nolineno }
> The `--force` flag is "*Necessary to restore metadata with thin pool volumes.*" (<a href="https://linux.die.net/man/8/vgcfgrestore">source</a>) 
    {: .prompt-info }

7. Check the Volume Group (VG) LVM metadata to ensure that the imported metadata is consistent:
```bash
sudo vgck --verbose vms
DEGRADED MODE. Incomplete RAID LVs will be processed.
Using volume group(s) on command line
Finding volume group "vms"
```
    {: .nolineno }

8. Recover the LVM Thin pool `thinpool`:
```bash
sudo lvconvert --repair vms/thinpool
```
    {: .nolineno }
> If you receive an error regarding "*mismatching transaction IDs*" you will need to perform the steps outlined in the <a href="#fixing-mismatching-transaction-ids">Fixing mismatching transaction IDs</a> (below) to resolve the mismatch _before_ proceeding with the remainder of the guide!
    {: .prompt-info }

9. Remove the temporary LVM Thin _pool_ metadata volume as directed after a successful import:
```bash
sudo lvremove vms/thinpool_meta0
```
    {: .nolineno }

10. Grow the Physical Volume (PV) (and therefore the contained Volume Group) to take advantage of the additional storage space on the software RAID 5 target:
```bash
sudo pvresize /dev/md1
```
    {: .nolineno }
> By default the size of the imported LVM environment (PVs + VGs + LVs) will be that of the size witnessed at the point of Volume Group metadata export (step 6.).
    {: .prompt-info }

11. Check that the Physical Volume (PV) has grown to occupy the available disk space:
```bash
sudo pvdisplay /dev/md1 | grep "PV Size"
```
    {: .nolineno }

12. Check that the Volume Group (VG) situated atop the recently grown Physical Volume (PV) has also grown in parallel to the PV:
```bash
sudo vgdisplay vms | grep "VG Size"
```
    {: .nolineno }

13. Activate the LVM Thin Pool:
```bash
sudo lvchange --activate y vms/thinpool`
[ 7022.717819] device-mapper: thin: Data device (dm-1) discard unsupported: Disabling discard passdown.
```
    {: .nolineno }
> When using a software RAID target (`mdadm` based) for the LVM Thin environment migration you will receive the following message (above) upon LVM Thinpool activation. Based off a RHEL thread (<a html="https://www.redhat.com/archives/dm-devel/2012-June/msg00118.html">here</a>) it appears that `mdadm` is the culprit for why "Discards" cannot be passed down from the LVM layer. This forces us to move the responsibility of "<a href="https://en.wikipedia.org/wiki/Trim_(computing)">trimming</a>" _all_ LVM Thin volumes and Thin snapshots (in order to reclaim unused blocks) to another aspect of the system; for example: using the `discard` option when mounting a filesystem situated onto the LVM Thin volume/snapshot for usage. 
    {: .prompt-warning }
> This particular example workaround has notable downsides (<a href="https://wiki.archlinux.org/index.php/Solid_State_Drives#Continuous_TRIM">source</a>) but would ensure that after each file deletion the unused blocks are reclaimed by the Thinpool *data* volume and can be used immediately by the Thin volume or Thin snapshot in question.
    {: .prompt-warning }

14. Import the LVM Thin Pool metadata contain details regarding Thin _volume(s)_ properties and their blocks shared with subsequent Thin _snapshot(s)_:
```bash
sudo thin_restore --input /mnt/storage/metadata/vms-thinpool_tmeta.xml 
                      --output /dev/mapper/vms-thinpool_tmeta
```
    {: .nolineno }
> The metadata XML file must be imported _before_ any Thin Pool/Volume/Snapshot resizing operation otherwise block mappings are inconsistent which will lead to a faulty LVM environment.
    {: .prompt-warning }

### Growing the migrated LVM Thin environment & Expanding GPT Partitions

At this stage the LVM Thin environment detailed in section 1 has been successfully imported in a "skeletal" manner; the LVM layout is present but the actual content of the Logical Volumes (LV) has not been restored. If you have no intention on growing any aspect of the migrated LVM Thin environment you will only need to perform steps 11, 12, and 17 to complete the entire process. 
  
1. Deactivate the LVM Thin Pool so we can proceed with growing the LVM Thin Pool's inbuilt `data` volume and corresponding `metadata` volume:
```bash
sudo lvchange --activate n vms/thinpool
```
    {: .nolineno }

2. Grow the LVM Thin Pool `data` volume to take advantage of the additional space in the Volume Group (VG):
```bash
sudo lvresize --extents 80%VG vms/thinpool
```
    {: .nolineno }

3. Grow the LVM Thin Pool `metadata` volume to accommodate for the size increase of the LVM Thin Pool `data` volume:
```bash
sudo lvresize --size +8M vms/thinpool_tmeta
```
    {: .nolineno }
> While no strict numbers exist I recommend growing the LVM Thin Pool `metadata` volume by the same ratio as the LVM Thin Pool `data` volume.
    {: .prompt-info }
> Overflowing the LVM Thin Pool *metadata* volume _will_ irrecoverably corrupt _all_ LVM Thin _volume(s)_ and Thin _snapshot(s)_
    {: .prompt-danger }

4. Remove the smaller LVM Thin Pool `metadata` spare Logical Volume:
```bash
sudo lvremove vms/lvol1_pmspare
```
    {: .nolineno }
> We perform this operation due to this particular <a href="https://www.redhat.com/archives/linux-lvm/2015-April/msg00017.html">LVM bug</a>. Essentially the spare metadata volume does not grow to mirror the primary Thin Pool `metadata` volume; effectively rendering the spare metadata volume unusable during Thin Pool recovery.
    {: .prompt-info }

5. Recreate the LVM Thin Pool `metadata` spare volume by "tricking" LVM into believing that the Thin Pool requires recovering. As per the HP support link (<a href="http://h20564.www2.hpe.com/hpsc/doc/public/display?docId=mmr_kc-0126722">here</a>), this will force LVM to recreate the spare `metadata` volume:
```bash
sudo lvconvert --repair vms/thinpool
```
    {: .nolineno }

6. Remove the extraneous LVM Thin `metadata` volume as instructed by the LVM Thin Pool recovery message in the previous step:
```bash
sudo lvremove vms/thinpool_meta0
```
    {: .nolineno }

7. Confirm that the recreated LVM Thin Pool `metadata` spare is the _same_ size as the primary Thin Pool `metadata` primary LV:
```bash
sudo lvs --all --options lv\_name,vg\_name,attr,lv\_size | grep 'spare\|meta'
[lvol1_pmspare]  vms  ewi------- 16.00m
[thinpool_tmeta] vms  ewi------- 16.00m
```
    {: .nolineno }

8. Activate the LVM Thin Pool and witness LVM identify the extra space for the dedicated Thin Pool `data` LV:
```bash
sudo lvchange --activate y vms/thinpool
```
    {: .nolineno }

9. Grow the LVM Thin Volume(s) and Thin Snapshot(s) as desired:
```bash
sudo lvresize --size +2G vms/thinvol1
sudo lvresize --size +2G vms/thinvol2
sudo lvresize --size +2G vms/thinvol3
sudo lvresize --size +2G vms/thinvol1_snap0
```
    {: .nolineno }

10. Confirm that the LVM Thin _volume(s)_ and Thin _snapshot(s)_ have grown accordingly:
```bash
sudo lvs --options lv_name,vg_name,attr,lv_size | grep thinvol*
thinvol1       vms  Vwi---tz--  4.00g
thinvol1_snap0 vms  Vwi---tz--  4.00g
thinvol2       vms  Vwi---tz--  4.00g
thinvol3       vms  Vwi---tz--  4.00g
```
    {: .nolineno }

11. Activate all LVM Thin _volume(s)_ and Thin _snapshot(s)_ ensuring to include the `--setactivationskip` flag so as to allow the selected LVM Thin _volume(s)_ and Thin _snapshot(s)_ (Logical Volumes) to be available (i.e. exposed block device nodes) at boot:
```bash
sudo lvchange --activate y --setactivationskip n vms/thinvol1
sudo lvchange --activate y --setactivationskip n vms/thinvol2
sudo lvchange --activate y --setactivationskip n vms/thinvol3
sudo lvchange --activate y --setactivationskip n vms/thinvol1_snap0
```
    {: .nolineno }

12. Restore the compressed disk images of the activated Thin _volume(s)_ and Thin _snapshot(s)_:
```bash
gunzip --stdout /mnt/storage/images/vms-thinvol1.raw.gz | sudo dd conv=sparse bs=4M of=/dev/mapper/vms-thinvol1
gunzip --stdout /mnt/storage/images/vms-thinvol2.raw.gz | sudo dd conv=sparse bs=4M of=/dev/mapper/vms-thinvol2
gunzip --stdout /mnt/storage/images/vms-thinvol3.raw.gz | sudo dd conv=sparse bs=4M of=/dev/mapper/vms-thinvol3
gunzip --stdout /mnt/storage/images/vms-thinvol1_snap0.raw.gz | sudo dd conv=sparse bs=4M of=/dev/mapper/vms-thinvol1_snap0
```
    {: .nolineno }
> Forgetting to use the `sparse` option (as part of the `dd` invocation) will result in the Thin _volume_ or Thin _snapshot_ having consumed 100% of its allocated space (assuming you did _not_ grow the Thin _volume_/_snapshot_). The reason for this is that while the majority of the blocks (for this particular test environment case) are "empty" (i.e. filled with 0's) they are being classified as "allocated" and therefore counting towards the total block usage. To remedy this perceived "full" state either run the `dd` utility with the `conv=sparse` option again or use the `fstrim` utility for discarding unused blocks.
    {: .prompt-info }

13. For each Thin _volume_ and Thin _snapshot_ duplicate the main GPT partition table (i.e. the one located at the front of the restored disk image) to the "new" end of the respective Logical Volume:
```bash
sudo sgdisk --move-second-header /dev/mapper/vms-thinvol1
sudo sgdisk --move-second-header /dev/mapper/vms-thinvol2
sudo sgdisk --move-second-header /dev/mapper/vms-thinvol3*
sudo sgdisk --move-second-header /dev/mapper/vms-thinvol1_snap0
```
    {: .nolineno }
> You may skip this section if you did not utilise GPT within your LVM Thin _volume(s)_ or Thin _snapshot(s)_.
    {: .prompt-info }

14. This test scenario has a single partition situated atop the GPT partition table which in turn resides on a Logical Volume (either as a Thin _volume_ or Thin _snapshot_). My aim was to expand the filesystem (contained within the single partition) in parallel with the growth of the underling Logical Volume (LV).
In order to grow a GPT partition you must first remove it and then recreate it setting the end sector value to the last physically available sector while simultaneously ensuring that the start sector aligns _exactly_ where it had done so previously:
```bash 
for id in 1 2 3 1_snap0
  sudo sgdisk --delete=1 /dev/mapper/vms-thinvol"${id}"
  sudo sgdisk --largest-new=1 --typecode=1:8300 /dev/mapper/vms-thinvol"${id}"
  sudo sgdisk --print /dev/mapper/vms-thinvol"${id}" | tail -n 2
done
```
    {: .nolineno }
> By default `sgdisk` will align the first partition to the 2048th sector (unless explicitly specified otherwise) which is what I used when originally creating the partition on the old LVM environment. You may skip this section if you did not utilise GPT within your LVM Thin Volume(s) or Thin Snapshot(s) - or simply do not wish to grow the single partition.
    {: .prompt-info }

15. Recreate all device mappings to the single GPT partition located atop each of the activated LVM Thin _volumes_ and Thin _snapshot_.
```bash
sudo kpartx -a /dev/mapper/vms-thinvol1
sudo kpartx -a /dev/mapper/vms-thinvol2
sudo kpartx -a /dev/mapper/vms-thinvol3
sudo kpartx -a /dev/mapper/vms-thinvol1_snap0
```
    {: .nolineno }
> You may skip this section if you did not utilise GPT within your LVM Thin Volume(s) or Thin Snapshot(s).
    {: .prompt-info }

16. Check the integrity of the Ext4 filesystem on each Thin _volume_ and Thin _snapshot_. This forced check was required before the `resize2fs` would permit the expansion of the underlying Ext4 filesystem: 
```bash
sudo e2fsck -f -y /dev/mapper/vms-thinvol1p1 > /dev/null
sudo e2fsck -f -y /dev/mapper/vms-thinvol2p1 > /dev/null
sudo e2fsck -f -y /dev/mapper/vms-thinvol3p1 > /dev/null
sudo e2fsck -f -y /dev/mapper/vms-thinvol1_snap0p1 > /dev/null
```
    {: .nolineno }

17. Resize the Ext4 filesystem situated within the GPT partition to consume the additional space now available within the partition:
```bash
sudo resize2fs /dev/mapper/vms-thinvol1p1
sudo resize2fs /dev/mapper/vms-thinvol2p1
sudo resize2fs /dev/mapper/vms-thinvol3p1
sudo resize2fs /dev/mapper/vms-thinvol1_snap0p1
```
    {: .nolineno }
> The `resize2fs` utility only resizes the <a href="https://en.wikipedia.org/wiki/Extended_file_system">Ext family</a> of filesystems, do not try to use it for other filesystems (e.g. XFS). Please refer to filesystem specific documentation/man pages with respect to resize operations for other filesystems. 
    {: .prompt-danger }

18. Mount the block device mappings of the GPT partition that reside on the LVM Thin _volume(s)_ and Thin _snapshot(s)_ ensuring to pass the `discard` option so as to transparently handle the "cleanup" of unused blocks:
```bash
sudo mount --options discard /dev/mapper/vms-thinvol1p1 /mnt/thinvol1
sudo mount --options discard /dev/mapper/vms-thinvol2p1 /mnt/thinvol2
sudo mount --options discard /dev/mapper/vms-thinvol3p1 /mnt/thinvol3
sudo mount --options discard /dev/mapper/vms-thinvol1_snap0p1 /mnt/thinvol1_snap0
```
    {: .nolineno }

At this stage you should be able to navigate and manipulate files within the mount points for the newly migrated and resized LVM Thin _volumes_ and Thin _snapshot_! Examining Linux's internal representation of the LVM environment: 
```bash
lsblk
NAME                             MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
vdd                              254:48   0   20G  0 disk
|-vdd2                           254:50   0   10G  0 part
| `-md0                            9:0    0   10G  0 raid1 /
|-vdd3                           254:51   0   10G  0 part 
| `-md1                            9:1    0   20G  0 raid5
|-vms-thinpool_tdata         252:1    0   16G  0 lvm
|   | `-vms-thinpool-tpool       252:2    0   16G  0 lvm
|   |   |-vms-thinvol3           252:6    0    4G  0 lvm   
|   |   | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|   |   |-vms-thinvol1           252:4    0    4G  0 lvm   
|   |   | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|   |   |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|   |   | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|   |   |-vms-thinvol2           252:5    0    4G  0 lvm   
|   |   | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|   |   `-vms-thinpool           252:3    0   16G  0 lvm   
|   `-vms-thinpool_tmeta         252:0    0   16M  0 lvm   
|     `-vms-thinpool-tpool       252:2    0   16G  0 lvm   
|       |-vms-thinvol3           252:6    0    4G  0 lvm   
|       | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|       |-vms-thinvol1           252:4    0    4G  0 lvm   
|       | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|       |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|       | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|       |-vms-thinvol2           252:5    0    4G  0 lvm   
|       | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|       `-vms-thinpool           252:3    0   16G  0 lvm   
`-vdd1                           254:49   0    1M  0 part  
vdb                              254:16   0   20G  0 disk  
`-vdb1                           254:17   0   20G  0 part  /mnt/storage
sr0                               11:0    1 1024M  0 rom   
vdc                              254:32   0   20G  0 disk  
|-vdc2                           254:34   0   10G  0 part  
| `-md0                            9:0    0   10G  0 raid1 /
|-vdc3                           254:35   0   10G  0 part  
| `-md1                            9:1    0   20G  0 raid5 
|   |-vms-thinpool_tdata         252:1    0   16G  0 lvm   
|   | `-vms-thinpool-tpool       252:2    0   16G  0 lvm   
|   |   |-vms-thinvol3           252:6    0    4G  0 lvm   
|   |   | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|   |   |-vms-thinvol1           252:4    0    4G  0 lvm   
|   |   | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|   |   |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|   |   | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|   |   |-vms-thinvol2           252:5    0    4G  0 lvm   
|   |   | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|   |   `-vms-thinpool           252:3    0   16G  0 lvm   
|   `-vms-thinpool_tmeta         252:0    0   16M  0 lvm   
|     `-vms-thinpool-tpool       252:2    0   16G  0 lvm   
|       |-vms-thinvol3           252:6    0    4G  0 lvm   
|       | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|       |-vms-thinvol1           252:4    0    4G  0 lvm   
|       | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|       |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|       | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|       |-vms-thinvol2           252:5    0    4G  0 lvm   
|       | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|       `-vms-thinpool           252:3    0   16G  0 lvm   
`-vdc1                           254:33   0    1M  0 part  
vda                              254:0    0   20G  0 disk  
|-vda2                           254:2    0   10G  0 part  
| `-md0                            9:0    0   10G  0 raid1 /
|-vda3                           254:3    0   10G  0 part  
| `-md1                            9:1    0   20G  0 raid5 
|   |-vms-thinpool_tdata         252:1    0   16G  0 lvm   
|   | `-vms-thinpool-tpool       252:2    0   16G  0 lvm   
|   |   |-vms-thinvol3           252:6    0    4G  0 lvm   
|   |   | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|   |   |-vms-thinvol1           252:4    0    4G  0 lvm   
|   |   | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|   |   |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|   |   | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|   |   |-vms-thinvol2           252:5    0    4G  0 lvm   
|   |   | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|   |   `-vms-thinpool           252:3    0   16G  0 lvm   
|   `-vms-thinpool_tmeta         252:0    0   16M  0 lvm   
|     `-vms-thinpool-tpool       252:2    0   16G  0 lvm   
|       |-vms-thinvol3           252:6    0    4G  0 lvm   
|       | `-vms-thinvol3p1       252:10   0    4G  0 part  /mnt/thinvol3
|       |-vms-thinvol1           252:4    0    4G  0 lvm   
|       | `-vms-thinvol1p1       252:8    0    4G  0 part  /mnt/thinvol1
|       |-vms-thinvol1_snap0     252:7    0    4G  0 lvm   
|       | `-vms-thinvol1_snap0p1 252:11   0    4G  0 part  /mnt/thinvol1_snap0
|       |-vms-thinvol2           252:5    0    4G  0 lvm   
|       | `-vms-thinvol2p1       252:9    0    4G  0 part  /mnt/thinvol2
|       `-vms-thinpool           252:3    0   16G  0 lvm   
`-vda1                           254:1    0    1M  0 part  
```
{: .nolineno }

```bash
sudo lvs --all --options lv_name,vg_name,attr,lv_size,data_percent
  LV               VG   Attr       LSize  Data% 
  [lvol1_pmspare]  vms  ewi------- 16.00m       
  thinpool         vms  twi-a-tz-- 15.98g 4.53  
  [thinpool_tdata] vms  Twi-ao---- 15.98g       
  [thinpool_tmeta] vms  ewi-ao---- 16.00m       
  thinvol1         vms  Vwi-aotz--  4.00g 4.59  
  thinvol1_snap0   vms  Vwi-aotz--  4.00g 4.52  
  thinvol2         vms  Vwi-aotz--  4.00g 4.91  
  thinvol3         vms  Vwi-aotz--  4.00g 4.85
```
{: .nolineno }

```bash
df -h
Filesystem                        Size  Used Avail Use% Mounted on
udev                               10M     0   10M   0% /dev
tmpfs                             401M  5.5M  396M   2% /run
/dev/md0                          9.8G  1.1G  8.2G  12% /
tmpfs                            1003M     0 1003M   0% /dev/shm
tmpfs                             5.0M     0  5.0M   0% /run/lock
tmpfs                            1003M     0 1003M   0% /sys/fs/cgroup
/dev/vdb1                          20G  922M   18G   5% /mnt/storage
/dev/mapper/vms-thinvol1p1        4.0G  120M  3.7G   4% /mnt/thinvol1
/dev/mapper/vms-thinvol2p1        4.0G  105M  3.7G   3% /mnt/thinvol2
/dev/mapper/vms-thinvol3p1        4.0G  104M  3.6G   3% /mnt/thinvol3
/dev/mapper/vms-thinvol1_snap0p1  4.0G  120M  3.7G   4% /mnt/thinvol1_snap0
```
{: .nolineno }
  
<hr>
### Fixing mismatching transaction IDs

"Thankfully" I encountered this issue when importing the test LVM environment on to the software RAID storage target. As mentioned in step 8 you only need to perform the following 4 steps to fix this issue should you have received an error similar to:
```bash
Transaction id 6 from pool "vms/thinpool" does not match repaired transaction id 0 from /dev/mapper/vms-lvol0_pmspare.
Logical volume "lvol1" created
WARNING: If everything works, remove "vms/thinpool_meta0".
WARNING: Use pvmove command to move "vms/thinpool_tmeta" on the best fitting PV.
```
{: .nolineno }

1. Deactivate the problematic Volume Group (VG):
```bash
sudo vgchange --activate n vms
```
    {: .nolineno }

2. Remove the problematic Volume Group (VG):
```bash
sudo vgremove --force --force vms
```
    {: .nolineno }
> You need to be "forceful" for this operation otherwise the same `mismatching transaction id` error resurfaces and prevents the removal!
    {: .prompt-info }

3. Edit the `transaction_id`'s value to that of the expected transaction id (as stated in the error message) from within the problematic Volume Group's (VG) metadata configuration file  `/mnt/storage/metadata/vms_backup`:
```bash
logical_volumes {
    thinpool {
        ...
        transaction_id = $VALID_ID
        ...
```
    {: .nolineno }

4. Re-import the *corrected* Volume Group (VG) metadata configuration file:
```bash
sudo vgcfgrestore --file /mnt/storage/metadata/vms-thinpool.vg --force vms
```
    {: .nolineno }
<hr>

## Limitations & Shortcomings 

Sadly the LVM Thin environment is not without some quite notable limitations that may make you re-consider it as a space efficient backing storage for KVM VM and LXC container usage. The issues outlined below are what negatively impacted my Libvirt (KVM) VM & LXC container directed workflows:

* Given that TRIM passdown support to a `mdadm` target was not implemented/supported by the particular version of utilities used I had to ensure that VMs were either performing routinely TRIM operations (e.g. `fstrim.timer`) or were using the questionable `discard` flag on supporting filesystems. 

* While the LXC toolset had the necessary arguments for creating LXC containers on LVM Thin Volumes I was unable to get easy access to the contents of the container as I would normally on a traditional filesystem installation.  

* Creating LVM Thin _snapshots_ with Libvirt is simply not possible as is with the version of Libvirt utilities I was using. Instead I had to a) use the `lvcreate` utility to create the LVM Thin _snapshot_ and then b) either clone the VM (via Libvirt ~ `virsh`) or edit the XML storage stanza of the VM to point to the new LVM Thin _snapshot_ block device node. The lack of a direct "internal snapshot" equivalent with LVM Thin Volumes/Snapshots resulted in a notable amount of management overhead emulating such a feature! 

* While not directly a disadvantage of LVM Thin environments, it is undeniable that an additional layer of block management introduces a greater risk of potential corruption. Although a workaround exists, the spare LVM Thin Pool `metadata` volume really should grow in parallel with the main LVM Thin Pool volume, such an oversight lead me question the maturity and stability of the state of thin provisioning in LVM.

* The notably greater complexity for initial configuration and environment migration when compared to a QCOW2 setup. Simpler approaches typically allow for quicker and more straightforward recovery procedures at the cost of reduced performance or greater storage consumption (in this case). 

## Final words

In closing, this guide has been written to serve as a step-by-step for myself in the near future when I add more SSDs to Octeron. While I had performed all the testing in the virtual machine (discussed in this guide) I was only approximately half way through writing this guide when I made the actual migration and expansion of the LVM thin environment on Octeron.

Funnily enough I have once again reviewed my VM management process since writing this guide and have decided against leveraging the LVM Thin environment for my day-to-day VM storage backend. For my particular workflow I was finding that the aforementioned limitations/shortcomings were too intrusive resulting in a reduced flexibility and increased management complexity cost for increased storage efficiency.

To address my initial issue of "golden" Debian GNU/Linux images becoming stale I have once more adopted the QEMU virtual disk image (QCOW2) file-based backend but now perform the following procedure to ensure that the "golden" image can stay up-to-date without corrupting external snapshots:

1. Temporarily shutdown the specified Debian GNU/Linux "golden" image via Libvirt (`virsh`). The virtual disk used is a `raw`, fully preallocated, 10GiB file that simply has a single Ext4 partition that houses all of '/' for simplicity.

2. Create a _single_ copy of the now offline Debian GNU/Linux "golden" image. Save the copy in a suitably named directory (e.g. project name) on a mounted filesystem situated upon a RAID 5 target on the SSDs.

3. Power up the Debian GNU/Linux "golden" image once more to ensure it can stay consistently up-to-date.

4. Create a QCOW2 external snapshot referencing the newly copied `raw` image as the backing image for *each* Debian GNU/Linux VM intended for use. If only a single Debian GNU/Linux image is required for the project in question then consider converting the `raw` image to the QCOW2 format for the benefits it brings. 

5. Define *each* Debian GNU/Linux VM utilising its corresponding QCOW2 external snapshot in Libvirt via `virsh`. 

This approaches costs 10GiBs of storage for _each_ project as it requires a static base image that is offline for external snapshots to work correctly. One notable benefit of this approach is the simplified process of archiving a project once completed. 
Using the LVM Thin environment would require me to delete the LVM Thin Volumes/Snapshots after their use and track their original size for recreation down the line. Moreover it simply may not be possible for LVM Thin _snapshots_ as it would require the LVM Thin Pool metadata Logical Volume to be altered to a previous state (invalidating/corrupting any project that was to be currently worked on!).

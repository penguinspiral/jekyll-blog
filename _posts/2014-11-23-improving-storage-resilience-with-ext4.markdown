---
title: Improving storage resilience with ext4
date: 2014-11-23 01:42:32
categories: [Storage]
tags: [s.m.a.r.t, gdisk, ext4]
---

There are numerous online guides for squeezing extra performance out of HDDs/SSDs - sometimes at the increased risk of losing data in the unfortunate case of a power outage (ext3/4 mount options: `data=writeback` and `barriers=0` I'm looking at you!). From what I've seen on Linux blogs/tutorials online there doesn't appear to be much in terms of improving resilience - possibly because its not as attractive as quicker I/O speeds.

## Intro

By "resilience" I mean the combination of efforts taken to preserve a working HDD/SSD state be it via backing up the GPT/MBR partition table, filesystem tuning, specific mount options, and S.M.A.R.T testing/reporting. My focus for this guide is on typical HDDs as I feel the likes of a large (1TB+) dedicated backup drives would benefit from improved resilience to data loss and/or filesystem corruption. Nonetheless simply increasing resilience is _not_ a sure fire solution to data integrity problems - make sure you perform routine backups!

> Please backup data _before_ applying any steps below
{: .prompt-danger }

### Packages

* `e2fsprogs`: 1.42.5-1.1
* `gdisk`: 0.8.5-1
* `smartmontools`: 5.41+svn3365-1
* `util-linux`: 2.20.1-5.3

## Backing up & restoring the GPT/MBR partition table

Although files are stored in the ext4 partition it is important to have a backup of the overall disk structure (partition table) as there's very little use in having your data on some filesystem in one of several partitions when your OS can't even detect where that partition (and consequently filesystem) is located.

### GPT

```bash
# Backup
sudo sgdisk --backup=/mnt/external/gpt_table_sdb.bin /dev/sdb

# Restore
sudo sgdisk --load-backup=/mnt/external/gpt_table_sdb.bin /dev/sdb
```

The backed up GPT partition file `gpt_table_sdb.bin` contains the first 34 LBA (Logical Block Addresses) of the block device `/dev/sdb` as well as including another copy of the GPT table _header_.

GPT creates a backup of its _partition entries_ and its _header_ at the very end of the disk as a redundancy measure, however I would still recommend creating an _external backup_ of the partition table in the unlikely event the duplicate GPT structure is unusable.
For those interested, further details of the overall GPT structure can be found <a href="http://en.wikipedia.org/wiki/GUID_Partition_Table">here</a>.

### MBR

```bash
# Backup
sudo sfdisk --dump /dev/sda > /mnt/external/mbr_table_sda.bin

# Restore
sudo sfdisk /dev/sda < /mnt/external/mbr_table_sda.bin
```

The MBR partition table utility equivalent `sfdisk` provides similar functionality to the `sgdisk` utility for backing up the partition table structure.

##  Ext4 filesystem tuning

> Before tuning the targeted Ext4 filesystem please ensure that it is not already mounted.
{: .prompt-warning }

```bash
sudo tune2fs -c 5 \
             -i 2W \
             -e remount-ro \
             -O mmp \
             -o journal_data,nodelalloc \
             /dev/sdb1
```

### tune2fs flags:

* `-c 5`: Perform a filesystem check every *5* _mounts_
* `-i 2W`: Perform a filesystem check every *2* _weeks_
* `-e remount-ro`: Attempts to mount the filesystem in _read-only_ when an error is encountered
* `-O mmp`: Enables "_Multiple Mount Protection_" option; prevents the filesystem from being mounted in multiple locations
* `-o journal_data`: Both _metadata_ and _user data_ is committed to the journal prior to being written into the main filesystem
* `,nodelalloc`: Disables the delayed allocation functionality in ext4

The values chosen for the filesystem check (using `e2fsck`) lends more to a system that is rebooted on a every-other-day basis as either metric will be quickly surpassed and a forced filesystem check incurred. The remount and mount protection options aren't in themselves too special they just provide more of a protected environment for the disk.

The specific ext4 mount options `journal_data` and `nodelalloc` are the real key tweaks here. Enabling `journal_data` ensures that all data is first stored in the journal )before_ user data is committed to the filesystem. This allows the I/O operations <u>as well as the data</u> to be replayed in case of interruption (e.g. a power fail) thus keeping the filesystem in a consistent state.

By having the `journal_data` mount option enabled we implicitly trigger the `nodealloc` option automatically - I simply wanted to add it explicitly to demonstrate what was occurring. The delayed allocation feature simply delays block allocation from a program's `write()` command, consequently allowing the block allocator to optimise where it finally places the blocks thus reducing overall fragmentation (on some workloads). By disabling it we do incur the fragmentation performance costs but we do not run the risk of <a href="https://en.wikipedia.org/wiki/Ext5#Delayed_allocation_and_potential_data_lossdata">potential data loss</a>.

I've omitted the `block_validity` mount option tweak because its a debugging focused feature which incurs a larger CPU and memory overhead for its metadata corruption prevention benefits.

## S.M.A.R.T configuration & automation

The majority of modern day harddisks have S.M.A.R.T "_Self-Monitoring, Analysis and Reporting Technology_" firmware inbuilt that is able to examine/report/test disk health at the hardware level. By configuring the S.M.A.R.T daemon a substantial insight into the disk's health over time can be ascertained allowing you to take action in advance (if in the unfortunate case the disk is failing).

### Interactive

```bash
sudo smartctl --smart=on \
              --offlineauto=on \
              --saveauto=on \
              /dev/sdb
```

First off we enable S.M.A.R.T functionality on the disk and pass two more flags (as recommended by the `smartctl(8)` man page):
* `--offlineauto=on`: Scans the disk every 4 hours for disk defects and saves the scanned information into the S.M.A.R.T attributes of the disk. Captures information that "online" checks cannot at the cost of a slight performance reduction
* `--saveauto=on`: Enabling the saving of device vendor-specific S.M.A.R.T attributes

### Daemon

```bash
# /etc/smartd.conf
/dev/sdb -o on -S on -l error -l selftest -C -s L/../../7/01 -m you@mailhost.com -t -I 194 -I 231

# Restart daemon
sudo systemctl restart smartd
```

#### smartd.conf flags:

* `-o on`: Enables collection of offline checks and updates the device's S.M.A.R.T attributes (identical to the interactive behaviour of smartctl but persists between reboots)
* `-S on`: Enables saving of device vendor-specific S.M.A.R.T attributes (identical to the interactive behaviour of smartctl but persists between reboots)
* `-l error`: Report (via e-mail) if the number of ATA errors in the S.M.A.R.T summary error log has increased since the last check
* `-l selftest`: Report (via e-mail) if the number of failed tests in the S.M.A.R.T Self-Test log has increased since the last check
* `-C`: Report (via e-mail) if the number of pending sectors (unstable/bad sectors requiring reallocation) is non-zero
* `-s L/../../7/01`: Start a long self test at 1AM on Sunday
* `-m you@mailhost.com`: The address to send the warning e-mail to. Requires an executable named "mail" in the same `$PATH` variable of the shell/environment (e.g. /bin/mail)
* `-t`: Tracking the changes of all device S.M.A.R.T attributes (listable with sudo smartctl -h /dev/sdb)
* `-I 194 -I 231`: Ignores device attribute number 192 & 231 when tracking changes in Attribute values. These values correspond to the temperature of the disk which despite only varying between a small, acceptable threshold may alter very often (i.e. get hotter when under sudden load) and consequently result in the sending of multiple worthless e-mails throughout the day.

## Mount options (fstab)

The two mount options mentioned in <A href="#ext4-filesystem-tuning">Ext4 filesystem tuning</A> are now passed to both the manual invocation of `mount` and to the `/etc/fstab` file:

```bash
# interactive
sudo mount -o data=journal,nodelalloc /dev/sdb /mnt/backup

# /etc/fstab
UUID=8d31792e-1f04-4e8d-b7b3-cda75d2b21f8       /mnt/backup     ext4    defaults,data=journal,nodelalloc     0       2
```

Using the UUID of the partition (`sudo blkid /dev/sdb1`) append the mount options to the `/etc/fstab` file so as to make the mount persistent between reboots. Notice the *2* value in the `pass` field, this means that the backup drive filesystem is checked _after_ the root disk's.


## Final Words

Hopefully these configurations can help you with creating a more resilient albeit slower HDD. I'd be interested in running some benchmark tests in the future to see how big the performance penalty is against both default configurations and increased I/O performance configurations. I'm sure there are a few performance tweaks I could apply here (e.g. mount option `noatime`) to improve performance whilst retaining the desired resilience.

If you've spotted any mistakes I've made or you'd like to comment/question any aspect feel free to leave a response in the comment box below.

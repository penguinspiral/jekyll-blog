---
title: Automating external storage backups with udisks-glue
date: 2015-02-17 01:17:37
categories: [Backup]
tags: [udisk, python]
---

The amount of administration time saved with effective automation can be quite staggering when calculated over several months. A well developed automation script/program can greatly reduce errors (typically introduced by human interaction), be ran at specified times throughout the day, perform reporting operations, and much more. 

Whenever I find myself repeating a "static" task more than two or three times on a regular basis I consider the possibility of automating said task. With automation I can accelerate my personal workflow whilst giving me an opportunity to improve my scripting skills in Bash or Python. 

## Intro

The process of backing up data is one of the prime cases where automation offers a wealth of benefits over manual interaction. Common uses of the `cron` daemon are for data backup purposes, e.g. `/home` partition data. 
> Be careful not to overload a `cron` backup job! Make sure the time between backup operations is sufficient before initiating another one.  
{: .prompt-warning }

Automating backups for external storage such as SD cards, memory sticks, or portable HDDs is a little trickier than the configuration of a typical `cron` job. 
Unlike `cron` the vast amount of people don't (usually) have an exact, specified time in which they connect their external storage - they tend to do it when they wish to access the stored media. 
Fortunately other utilities exist for handling this uncertainty. 

This guide covers the necessary preparation to:
1. Automount a specified partition of a generic external storage device
2. Execute command(s)/script(s) _post_ mount

### Packages

* `dbus`: 1.6.8-1+deb7u5
* `policykit-1`: 0.105-3
* `udisks`: 1.0.4-7wheezy1
* `udisks-glue`: 1.3.4-1
* `wget`: 1.13.4-3+deb7u2

## Automounting

<a href="https://www.freedesktop.org/wiki/Software/udisks/">udisks</a> operates as:
* A daemon, `udisks-daemon`, implementing a D-Bus interface for polling, enumerating, and querying storage devices
* A CLI utility, `udisksctl`, for interactive storage query and daemon interaction; user actions are restricted via `polkit` (PolicyKit)

Unlike traditional daemons which are commonly invoked through init scripts at startup `udisks-daemon` is dynamically loaded by D-Bus when its services are requested.
All queries and actions through either the daemon or commandline utility are done so with <a href="https://en.wikipedia.org/wiki/Polkit">Polkit</a> configurable user privileges.
The relationship between all these utilities can be roughly identified as:  

> D-Bus <-- PolicyKit <-- udisks <-- uisks-glue

<a href="https://manpages.debian.org/wheezy/udisks-glue/udisks-glue.conf.5">udisks-glue</a> builds upon udisks by providing a simple mechanism for running certain _matches_ from preconfigured _filters_. This enables the execution of command(s)/script(s) _post_ mount (and unmount) of specified filesystems.

> This guide covers `udisks1` configuration/operation _not_ the Gnome DE constrained udisks2!
{: .prompt-warning }

1. Install the necessary packages:
```bash
sudo apt-get install dbus policykit-1 udisks udisks-glue
```

2. Create a PolicyKit rule file, `/etc/polkit-1/localauthority/50-local.d/10-storage.pkla`, permitting users of the `floppy` group to automount devices:
```bash
sudo editor /etc/polkit-1/localauthority/50-local.d/10-storage.pkla
...
[automount]
	Identity=user-group:floppy
    Action=org.freedesktop.udisks.filesystem-mount
    ResultAny=yes
```
Debian 7 uses the `floppy` group for all removable external storage (i.e. SD card) which, upon initial installation of a Debian 7 OS, the user will be a member of.

3. Restart the D-Bus service in order to restart the PolicyKit daemon:
```bash
sudo service dbus restart
```
In graphical desktop environments it is most likely safer to restart the display manager by logging out and logging back in (Credits: <a href="http://unix.stackexchange.com/questions/39203/how-to-restart-polkitd">here</a>)

4. Check the D-Bus service is working correctly by listing the services currently available:
```bash
dbus-send --system \
             --print-reply \
             --type=method_call \
             --dest=org.freedesktop.DBus /org/freedestop/DBus org.freedesktop.DBus.ListNames
⠀
# Response should be something similar to this...
method return sender=org.freedesktop.DBus -> dest=:1.0 reply_serial=2
array [
	string "org.freedesktop.DBus"
    string ":1.0"  
]
```

5. Now connect the external storage device which is intended to be automounted by the system and identify the targeted partition's UUID:
```bash
sudo blkid /dev/sdb1 --match-tag=UUID --output=value
```

6. Test that PolicyKit's permissions have been correctly applied by attempting to mount the targeted partition as an unprivileged user:
```bash
udisksctl mount /dev/disk/by-uuid/$UUID_OBTAINED_IN_STEP_5
⠀
# Verify successful mount
grep /dev/disk/by-uuid/$UUID_OBTAINED_IN_STEP_5 /etc/mtab
```

7. If `udisks` operated in accordance with the PolicyKit rule made in step 2. (i.e. mounted without errors as a standard user) create a generic `udisks-glue` configuration file `~/.udisks-glue.conf`:
```bash
editor ~/.udisks-glue.conf
⠀
# Filters
filter externalStorageDevice
{
  optical = false
  partition_table = false
  usage = filesystem
  uuid = $UUID_OBTAINED_IN_STEP_5
}
⠀
# Rules 
match externalStorageDevice
{
  automount = true
  automount_filesystem = vfat
  automount_options = sync
  post_mount_command = "/path/to/an/executable/./script.sh"
  post_unmount_command = "mount-notify unmounted %device_file %mount_point"
}
```
For more examples see: <a href="https://manpages.debian.org/wheezy/udisks-glue/udisks-glue.conf.5">man udisks-glue.conf</a>

8. Now we can grab a SysVinit script for ensuring `udisks-glue` starts at boot time (Credits : <a href="https://gist.github.com/abythell">Andrew Bythell</a> ~ _abythell_):
```bash
wget https://gist.githubusercontent.com/abythell/5399914/raw/33ed0e67c05c8aabed043151a25efffc298b86ac/udisks-glue 
```

9. For our user specified configuration we need to alter the downloaded SysVinit script slightly:
```bash
sed --inplace "s/\/etc\/udisks-glue.conf/\/home\/$USER\/.udisks-glue.conf/g" ~/udisks-glue
```

10. Now we need to make the SysVinit script executable. To do this change its ownership to `root`, place it in the `/etc/init.d/` directory, and run `update.rc` to automatically symlink the script for the default runlevels:
```bash
chmod 755 ~/udisks-glue
sudo chown root:root ~/udisks-glue
sudo mv ~/udisks-glue /etc/init.d
sudo update-rc.d udisks-glue defaults
```

11. Test the `udisks-glue` script by unmounting the partition, disconnect the external storage device, and finally reconnecting the external storage device:
```bash
udisksctl unmount /dev/disk/by-uuid/$UUID_OBTAINED_IN_STEP_5
```

12. Start the `udisks-glue` makeshift daemon:
```bash
sudo service udisks-glue start
```

13. Finally connect the external storage device with the targeted partition to the system. See that the device was located and that the desired partition was actually mounted:
```
# Verify device detection
dmesg | tail --lines 15
⠀
# Verify mount
grep /dev/disk/by-uuid/$UUID_OBTAINED_IN_STEP_5 /etc/mtab
```
If the command desired isn't executed:
* Check that you can still mount with `udisksctl`
* Verify the URL and permission bits of the script

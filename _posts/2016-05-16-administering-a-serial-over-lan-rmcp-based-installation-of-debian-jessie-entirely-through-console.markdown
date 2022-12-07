---
title: Administering a Serial over LAN (RMCP+) installation of Debian Jessie
date: 2016-05-16 05:27:00
categories: [Installer]
tags: [sol, ipmi, samba]
---

The recent addition of four 16GB DDR3 DIMM modules to my VM server (Octeron) has seen its RAM capacity double from 64GB to 128GB thus facilitating the creation of even bigger virtualised environments. Subsequent testing of the new RAM modules with <a href="http://www.memtest86.com/">Memtest86</a> had me once again venture into Octeron's enterprise grade BIOS remotely via the Java powered iKVM. It was here that I stumbled across the <a href="https://en.wikipedia.org/wiki/Serial_over_LAN">Serial-Over-LAN</a> (SOL) functionality which got me considering the possibility of performing a traditional Debian GNU/Linux installation completely through a SOL session.  

## Intro

Unlike the iKVM interface which requires a preexisting Java Runtime Environment (JRE) and a windowing system (e.g. <a href="https://en.wikipedia.org/wiki/X_Window_System">X11</a>), SOL can be accessed from "traditional" terminals. This flexibility not only enables the interaction from purely console based TTY terminals (typically found in server environments) but also provides the necessary foundation for access via terminal emulators across various operating systems/platforms (e.g. <a href="https://play.google.com/store/apps/details?id=jackpal.androidterm&hl=en">Terminal Emulator</a> for Android).

Since version 1.5 of Intel's Intelligent Platform Management Interface (IPMI) SOL has been included as part of the core specification (<a href="http://www.intel.com/content/www/us/en/servers/ipmi/ipmi-v1-5-intro.html">source</a>) and is accessed via the Remote Management Control Protocol (RMCP). The advent of IPMI 2.0 in 2004 ushered in RMCPs successor, "RMCP+", which built upon RMCP's foundation by enhancing various security and authentication mechanisms (details of which can be found <a href="http://www.intel.com/content/www/us/en/servers/ipmi/new-ipmi-specifications.html">here</a>).

Examining SuperMicro's product specification for the enterprise grade <a href="http://www.supermicro.nl/Aplus/motherboard/Opteron4000/SR56x0/H8DCL-iF.cfm">H8DCL-iF</a> motherboard used by Octeron reveals the complete implementation of the IPMI 2.0 specification. Unlike my other blog entries, this post is a purely investigatory endeavor which will probably not be too applicable for the vast majority of user environments. Nevertheless it illustrates the remarkable flexibility with today's CLI software utilities for facilitating such an operation. 
### Prerequisites

1. Network connectivity to a host with a SuperMicro motherboard that implements *at least* the IPMI 1.5 specification (this guide assumes IPMI 2.0 support) for SOL support. Users with active firewalls in their network environment must ensure that port `UDP/623` is permitted between their client machine and the IPMI host. 

2. Administrator or Operator credentials (difference explained <a href="https://www.thomas-krenn.com/en/wiki/IPMI_Basics#Session">here</a>) when authenticating with the IPMI host. These elevated privileges are necessary for power cycling the IPMI host in addition to attaching the virtual media (ISO image).

3. Enabling and configuring SOL as appropriate from within the BIOS menu. On Octeron I set the Serial Port Number to `COM2\*` (default ~ see screenshot below) which translates to `/dev/ttyS1` within Debian GNU/Linux. Disabling `Redirection After BIOS POST` was necessary otherwise: 1. The GRUB2 bootloader menu would not be visible and 2. An interactive `getty` session was not presented upon successful boot (verified by SSH).
![Octeron's SOL configuration](/assets/img/posts/2016-05-16-administering-a-serial-over-lan-rmcp-based-installation-of-debian-jessie-entirely-through-console/SOL.jpg)

4. A Samba server that the IPMI host can communicate with over the network via the SMB protocol (i.e. `TCP/445`, `TCP/139`, `UDP/137`, and `UDP/138`). The Debian Jessie installer ISO must be stored in an exported/shared directory that can be accessed by a preexisting user with at _least_ read only privileges. This guide outlines the basics of setting up a simple, insecure Samba server; it should not be used in production!
Note: During installation the connection between the IPMI host and Samba server **must** remain intact otherwise the `debian-installer` will likely fail.

### Packages

* `wget`: 1.13.4-3+deb7u2
* `genisoimage`: 9:1.1.11-3
* `samba`: 2:3.6.6-6+deb7u6
* `ipmitool`: 1.8.14-4
* `curl`: 7.38.0-4+deb8u3

## Installation environment 

To boot a Debian GNU/Linux installation ISO we must first satisfy the prerequisites listed above as well as enabling serial access within the Debian installer itself.
At this stage I am *assuming* that you have satisfied all prerequisites and are in the console of the client host.  

### Serial enabled Debian GNU/Linux installer ISO

Unfortunately the latest Debian GNU/Linux Jessie 8.4 installer ISO still does _not_ have serial access enabled within its (MBR driven) `isolinux` bootloader. The default behaviour of the Debian installer at the `isolinux` bootloader phase is to wait _indefinitely_ for a user input (i.e. selecting an installation option). 
This behaviour is problematic as we cannot proceed to select an installation option via a console.

Thankfully I've already encountered and solved this issue before when configuring Debian installer ISOs for my Libvirt VM environments (<a href="https://myles.sh/enabling-console-access-within-libvirt-kvm-hosted-debian-images/">here</a>). The steps below follow the same vein as my previous workflow but accommodate for the small changes made in the Debian installation ISO since then.

1. Download the latest Debian GNU/Linux Jessie 8.4 netinst ISO image:
```bash
wget --directory-prefix=$HOME \
        https://cdimage.debian.org/debian-cd/8.4.0/amd64/iso-cd/debian-8.4.0-amd64-netinst.iso
```
    {: .nolineno }

2. Setup a loopback device node (assuming `/dev/loop0` for the remainder of this section) for mounting the Debian GNU/Linux Jessie 8.4 netinst ISO. Once mounted we can begin copying its contents and making the necessary alterations to enable serial booting: 
```bash
sudo losetup --find --show ~/debian-8.4.0-amd64-netinst.iso
```
    {: .nolineno }

3. Create a dedicated mount point for the loopback device node established in the previous step:
```bash
sudo mkdir /mnt/debian-8.4.0-amd64-netinst-orig
```
    {: .nolineno }

4. Mount the loopback device node to the dedicated mount point created in the previous step. As is with `ISO9660` images the mount will automatically be in a read-only state:
```bash
sudo mount -t iso9660 /dev/loop0 /mnt/debian-8.4.0-amd64-netinst-orig
```
    {: .nolineno }

5. Create a dedicated directory for storing the modified contents of the Debian GNU/Linux Jessie netinst ISO. For simplicity I've selected the current user's home directory:
```bash
mkdir ~/debian-8.4.0-amd64-netinst-serial
```
    {: .nolineno }

6. Copy the contents of the Debian GNU/Linux Jessie netinst ISO to the directory created in the previous step. From this point onwards we can begin making the necessary alterations to enable serial access:
```bash
cp --verbose --recursive /mnt/debian-8.4.0-amd64-netinst-orig ~/debian-8.4.0-amd64-netinst-serial
```
    {: .nolineno }
We _must_ copy the "hidden" `.disk` directory and its contents as these are required when regenerating the altered ISO image.

7. Modify the permissions of certain files so as to permit write access to them. These particular configuration files will either be directly edited or overwritten during ISO generation:
```bash
chmod 644 ~/debian-8.4.0-amd64-netinst-serial/debian-8.4.0-amd64-netinst-orig/isolinux/{isolinux,txt}.cfg
chmod 644 ~/debian-8.4.0-amd64-netinst-serial/debian-8.4.0-amd64-netinst-orig/isolinux/isolinux.bin
```
    {: .nolineno }

8. Edit `~/debian-8.4.0-amd64-netinst-serial/debian-8.4.0-amd64-netinst-orig/isolinux/stdmenu.cfg` and prepend the following serial console command to the top of the file:
```bash
# stdmenu.cfg
serial 1 115200
```
    {: .nolineno }
Being a derivative of <a href="https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX">SYSLINUX</a>, <a href="https://wiki.syslinux.org/wiki/index.php?title=ISOLINUX">ISOLINUX</a> is capable of displaying its bootloader menu over a specified serial port/channel at various baud rates. The configuration we apply at this stage informs ISOLINUX to use serial port/channel 1 (equates to `COM2`) at a baud rate of 115200 bits per second so as to present an interactive menu via the serial console. 
More details about serial console configuration within SYSLINUX/ISOLINUX/PXELINUX can be found <a href="http://www.tldp.org/HOWTO/Remote-Serial-Console-HOWTO/configure-boot-loader-syslinux.html">here</a>.

9. Edit `~/debian-8.4.0-amd64-netinst-serial/debian-8.4.0-amd64-netinst-orig/isolinux/txt.cfg` and append the required serial configuration arguments to the Linux kernel and initrd pair booted when selecting the default "install" option in the `isolinux` bootloader menu:
```bash
# txt.cfg
append initrd=/install.amd/initrd.gz --- quiet console=ttyS1,115200n8
```
    {: .nolineno }
Remove the `VGA=766` option to ensure that the targeted serial port is used instead. As we have not configured any other boot options (i.e. "Advanced options" boot menu selection) we _must_ use this option when installing Debian GNU/Linux Jessie 8.4 via SOL. 

10. Generate the serial enabled Debian installer ISO image from the edited ISO contents:
```bash
genisoimage \
  -o ~/debian-8.4.0-amd64-netinst-serial-ipmi.iso \
  -r \
  -J \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  ~/debian-8.4.0-amd64-netinst-serial/debian-8.4.0-amd64-netinst-orig/
```
    {: .nolineno }
For brevity I've omitted an explanation of each argument/flag passed to the `genisoimage` binary. For those interested in what these arguments/flags imply you can find out more in my previous post <a href="https://myles.sh/enabling-console-access-within-libvirt-kvm-hosted-debian-images/">here</a>. 

11. As we have now successfully generated a serial enabled Debian GNU/Linux Jessie netinst ISO we can go about unmounting the loopback device node: 
```bash
sudo umount /dev/loop0
rm --recursive ~/debian-8.4.0-amd64-netinst-serial
```
    {: .nolineno }

12. Copy/Move the serial enabled Debian GNU/Linux Jessie netinst* ISO (generated in step 10.) to your Samba server.

### Samba server configuration

In my environment I provisioned a simple Samba server from within an unprivileged LXC container on my client machine. I have outlined the few steps necessary for configuring a functional Samba server that provides the serial enabled Debian GNU/Linux installer ISO to the IPMI host.
As mentioned previously, the following Samba configuration is **not** recommended for usage in a production environment.

1. Install the Samba server Debian package:
```bash
sudo apt-get install samba
```
    {: .nolineno }

2. Edit the global Samba server configuration file `/etc/samba/smb.conf` and append the following export/share stanza:
```
[ipmi]
  comment = IPMI Samba share
  path = /path/to/dir/containing/serial_iso
  read only = yes
  guest ok = no
```
    {: .nolineno }
The `path` variable must point to a directory containing the serial enabled Debian GNU/Linux Jessie netinst ISO. Moreover the exported/shared directory and the ISO image must have (at *least*) read-only privileges for (at *least*) the current user.

3. Add the owner of the Debian GNU/Linux installer ISO and exported/shared directory to the internal Samba database. We will use this particular user for authenticating with the Samba server when accessing the ISO image from the IPMI host.
```bash
sudo smbpasswd -a USERNAME
```
    {: .nolineno }
I would recommend against using the _same_ password as that of your current system user as we will need to save the Samba user password in a plaintext file later on! 

4. Restart the Samba server to ensure that the user and share/export configurations are applied: 
```bash
sudo systemctl restart smbd
```
    {: .nolineno }

## Installing Debian via SOL

If you have managed to satisfy all four prerequisites and have correctly exported/shared a serial enabled Debian GNU/Linux Jessie netinst ISO then you have successfully prepared your environment.
With the necessary foundations in place we can now commence the installation of the serial enabled Debian GNU/Linux installer ISO completely via SOL.
 
1. Install the `ipmitool` userspace utility for communicating with the IPMI host. Beyond providing the SOL shell, `ipmitool` facilitates "_printing FRU information, LAN configuration, sensor readings, and remote chassis power control._" (<a href="https://linux.die.net/man/1/ipmitool">source</a>):
```bash
sudo apt-get install ipmitool
```
    {: .nolineno }

2. Download the `supermicro-mount-iso.sh` Bash script (credits: <a href="https://gist.github.com/DavidWittman">David Wittman</a>). This script employs `curl` for interacting with the IPMI host's web interface and setting the appropriate CD/ISO text boxes for "mounting" the SMB/CIFS exported/shared Debian ISO:
```bash
wget --directory-prefix=$HOME \
         https://gist.githubusercontent.com/DavidWittman/eaee7d909cef478ab898/raw/040e4f788ca875b7949286cdadc44a432334ae8f/supermicro-mount-iso.sh
```
    {: .nolineno }

3. Alter the permission of the newly downloaded `supermicro-mount-iso.sh` Bash script to enable executable permissions:
```bash
chmod 744 ~/supermicro-mount-iso.sh
```
    {: .nolineno }

4. Edit the `supermicro-mount-iso.sh` script and populate both the IPMI and Samba login credentials appropriate for your environment:
```bash
# IPMI Credentials
USER=admin_or_operator
PASSWORD=password_for_ipmi_admin_or_operator
...
# Samba Credentials
[...]--data-urlencode "user=samba_user" --data-urlencode "pwd=samba_user_password"[...]
```
    {: .nolineno }
The source code for the two CGI web script files (`virtual_media_share_img.cgi` and `uisopin.cgi`) `curl` interacts with in the `supermicro-mount-iso.sh` Bash script can be examined in Google Chrome via: Developer Tools -> Sources -> CGI -> `[https]://ipmi-ip/cgi/url_redirect.cgi?url_name=vm_cdrom`. Ensure you have navigated to the Virtual Media -> CD-ROM Image page.

5. With the correct user credentials for both IPMI and Samba in place we can now proceed to execute the script:
```bash
~/./supermicro-mount-iso.sh $IP_IPMI_HOST $IP_SAMBA_SERVER '\ipmi\debian-8.4.0-amd64-netinst-serial-ipmi.iso'
```
    {: .nolineno }
Upon execution the script will perform the AJAX call `virtual_media_share_img.cgi` (located within JS function: `SetSharedImageConfig()`) which populates the correct input text boxes with the configuration arguments passed to the Bash script. 
Once completed it proceeds to pause momentarily (`sleep 1`) and then calls the second and final AJAX call `uisopin.cgi` (located within JS function `MountSharedImage()`) which, with the Samba configuration provided, attempts to mount the remote Debian installer ISO.

6. Ensure the targeted IPMI host is powered but is not currently running an OS.

7. Use the `ipmitool` utility to remote power on and connect to the SOL channel of the targeted IPMI host: 
```bash
ipmitool -I lanplus -H $IP_OF_IPMI -U $ADMIN_OR_OPERATOR -P $IPMI_PASSWORD power start && \
ipmitool -I lanplus -H $IP_OF_IPMI -U $ADMIN_OR_OPERATOR -P $IPMI_PASSWORD sol activate 
```
    {: .nolineno }
The reason I employ the Bash 'AND' operator (`&&`) is so access is gained to the SOL interface as soon as the IPMI host is powered on. Unless the BIOS boot order has been configured to select the virtual media (i.e. the remote Samba ISO mount) option first we will need to intervene and select the correct boot media option.
For brevity I have omitted both an explanation of the flags presented (most are self-explanatory) as well as any advanced authentication/security mechanisms employed by the RMCP+ protocol. For those interested the details of both of these omitted aspects can be found in the man pages of <a href="https://linux.die.net/man/1/ipmitool">ipmitool(1)</a>.

8. During its initial visual POST phase the SuperMicro motherboard firmware scans through all the available RAM performing what appears to be a basic check in addition to listing various peripherals it has discovered. 
While it is checking the available RAM press the <kbd>F11</kbd> (or <kbd>F3</kbd>) key from within the SOL shell to enter the "One time boot menu". After the BIOS has finished initialising all its peripherals (e.g. SAS PCI-E card) and onboard NICs you should be presented with a bootable option list:
```bash
****************************************
*      Please select boot device:      *
* USB:IPMI Virtual CDROM               *
* RAID:P0-Samsung SSD 850              *
* USB:IPMI Virtual Disk                *
* Network:IBA GE Slot 0100 v1353       *
*                                      *
*                                      *
*                                      *
*                                      *
*                                      *
*                                      *
****************************************
*      * and * to move selection       *
*     ENTER to select boot device      *
*      ESC to boot using defaults      *
****************************************
```
    {: .nolineno }
Select the `USB:IPMI Virtual CDROM` option to begin booting the serial console enabled Debian GNU/Linux Jessie netinst ISO. Once selected my SuperMicro motherboard gave off two short sharp beeps to indicate it was now using the remote virtual media as its boot media.

9. Shortly after choosing the `USB:IPMI Virtual CDROM` option you should be presented with the following ISOLINUX bootloader menu screen from within your SOL session (dependent upon your network speed from client to IPMI host):
```bash
┌───────────────────────────────────────┐
    Debian GNU/Linux installer boot menu  
├───────────────────────────────────────┤
   Install                               
   Graphical install                     
   Advanced options                    > 
   Help                                  
   Install with speech synthesis         
└───────────────────────────────────────┘
Press ENTER to boot or TAB to edit a menu entry  
```
    {: .nolineno }
As mentioned previously, in this guide we have only configured the `Install` option to utilise both the correct serial port (for SOL) and baud rate so proceed by pressing <kbd>Enter</kbd> on the keyboard to commence the installation process.
> Selecting any other installation option (e.g. "`Graphical install`") will leave you with a blank console where you cannot continue the installation process.
    {: .prompt-warning }
If you accidentally enter this state restart your IPMI host and perform steps 7. to 9. once more.

10. Follow the menu driven, <a href="https://en.wikipedia.org/wiki/Ncurses">ncurses</a> based installation procedure configuring the IPMI host as desired for a minimal Debian GNU/Linux Jessie 8.4 environment. 
Upon installing the GRUB2 bootloader ensure that you enter the installation menu by pressing <kbd>ESC</kbd>,<kbd>ESC</kbd>. Once presented with the installation/configuration menu list select the `Execute a shell` option.

11. Select `Continue` when the prompt explaining the <a href="https://en.wikipedia.org/wiki/Almquist_shell">Almquist shell</a> is displayed. The reason for entering a shell session within the installation media is so we can correctly configure both the GRUB2 bootloader and systemd to provide a serial console interface on the correct port/channel (and baud rate) upon subsequent boots.

12. For GRUB2 to regenerate its `/boot/grub/grub.cfg` configuration file with the necessary serial configurations that will work with the preconfigured SOL session we will need to perform a series of `mount` operations:
```bash
mount --bind /dev /target/bind
mount --types sysfs /target/sysfs 
mount --types proc /target/proc
```
    {: .nolineno }

13. Proceed to `chroot` into the installation path (`/target`) so we can begin making the necessary modifications in a familiar environment:
```bash
TERM=linux chroot /target
```
    {: .nolineno }

14. Take advantage of the `root` account already configured for the target installation and enter an interactive Bash shell:
```bash
su root
```
    {: .nolineno }

### **GRUB2** configuration

All operations within this section are within the context of the `chroot`'d environment as the `root` user set in <a href="#installing-debian-via-sol">Installing Debian via SOL</a> steps 13. & 14.

1. With the inbuilt `nano` text editor modify the GRUB2 configuration file `/etc/default/grub` so that the GRUB2 menu is displayed over the correct serial console port/channel (`COM2`) and at the correct baud rate:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS1,115200n8"
...
## GRUB2 menu over serial console
GRUB_TERMINAL=serial
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=1 --word=8 --parity=no --stop=1"
```
    {: .nolineno }
The  `GRUB_CMDLINE_LINUX_DEFAULT` option appends the serial console configuration onto each "normal" (i.e. non-recovery) Linux kernel entry in the GRUB2 menu. While not 100% necessary I find it useful to see the kernel output log during boot in case of any boot time issues stopping a login shell.
The `GRUB_SERIAL_COMMAND` and `GRUB_TERMINAL` options configure GRUB2 itself to use the specified serial port/channel and baud rate when presenting its bootloader menu. As per the <a href="https://www.gnu.org/software/grub/manual/html_node/Serial-terminal.html">documentation</a>: "_[...] if you want to use `COM2`, you must specify `--unit=1` [...]_".

2. Regenerate the GRUB2 configuration file `/boot/grub/grub.cfg` to apply the serial console alterations/additions:
```bash
update-grub
```
    {: .nolineno }

### **systemd** configuration

All operations within this section are within the context of the `chroot`'d environment as the `root` user set in <a href="#installing-debian-via-sol">Installing Debian via SOL</a> steps 13. & 14.

1. Instruct systemd to present a `getty` login prompt on `/dev/ttyS1` at boot:
```bash
systemctl enable serial-getty@ttyS1.service
```
    {: .nolineno }

### Cleanup

2. Exit the `root` Bash shell, `chroot` environment, and `ash` shell to return back to the Debian installation menu:
```bash
exit # 1. Exits root Bash shell
exit # 2. Exits chroot
exit # 3. Exits ash shell
```
    {: .nolineno }

3. Select the `Finish installation` option in the installer menu and allow the IPMI host to reboot. 
> Ensure you select this option and do _not_ perform the reboot from within the `ash` shell! This final installation step configures the standard user specified earlier in the installation process in addition to other cleanup operations.
    {: .prompt-warning }

4. Unmount the loaded Samba exported/shared Debian GNU/Linux Jessie 8.4 netinst ISO from the BMC. This step is performed by the client machine: 
```bash
SESSION_ID=$(curl -d "name=${USER}&pwd=${PASS}" "https://${IPMI_HOST}/cgi/login.cgi" --silent --insecure -i | awk '/Set-Cookie/ && NR != 2 { print $2 }')
curl "https://${IPMI_HOST}/cgi/uisopout.cgi" -H "Cookie: ${SESSION_ID}" --silent --insecure --data ""
```
    {: .nolineno }
Substituting the `${USER}`, `${PASS}`, and `${IPMI_HOST}` with the username, password, and IP address of the IPMI host respectively. 

Upon reboot the SOL shell should (*assuming* you have not exited the session at this point) behave as follows: 

1. Clear all text/visual artifacts from the Debian installation environment. 
2. Display various SuperMicro BIOS initialisation screens during bootup. 
3. Present an interactive GRUB2 menu once BIOS hands over control to the bootloader. 
4. Display the boot messages of the specified (for non-recovery kernels) Linux kernel as it initialises various hardware subsystems/peripherals.
5. Present a `getty` login shell for providing access to the IPMI host in a similar fashion as a directly connected TTY.

## Final Words

Given the flexibility of iKVM in tandem with the ubiquitous nature of Java found in today's computers, I don't believe many users will find this particular investigation effort of mine too useful! Nevertheless it illustrates the capabilities of a purely CLI environment by making it possible to bootstrap a Debian GNU/Linux Operating System on modern IPMI hardware _entirely_ remotely.

An enjoyable aspect of this investigation was the broadening of my own understanding in respect to what particular utilities such as `curl` are capable of (i.e. interacting with AJAX). The creative process involved when transitioning from having a familiarity/understanding of individual utilities to concocting a plausible "recipe" (i.e. bringing these utilities together in a way you hadn't considered before) is a nice change from the traditional system administration driven focuses of greater efficiency, security, availability, resilience, etc via subsystem(s) manipulation.

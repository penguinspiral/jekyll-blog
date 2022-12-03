---
title: Installing Debian Jessie on a Dell XPS 13 9350 via a custom Debian Installer ISO with complete hardware support
date: 2016-03-16 11:35:00
categories: [Installer]
tags: [dell, xps, broadcom, installer]
---

Since its initial announcement at CES back in January 2015 I've kept a close eye on the progression of the venerable Dell XPS 13 9343 Ultrabook. The 9343's evolutionary successor, the "9350", was released later that year and boasted various hardware improvements in addition to having substituted the mini-DisplayPort for a more versatile Thunderbolt 3/USB 3.1 Gen 2 port. 

## Intro

With my Dell Studio 1558 dying[^footnote] on me in the latter end of the third year at Loughborough University I ended up getting a cheap $350 replacement in the form of a Lenovo G500s that continues to serve me well to this day. Being on the more affordable, entry-level side of the hardware component scale the G500s never really excelled in any particular aspect.

Enter the Dell XPS 13 9350. With its countless positive reviews from numerous tech sites (<a href="http://www.zdnet.com/product/dell-xps-13-2015/">ZDNet</a>, <a href="http://www.computershopper.com/laptops/reviews/dell-xps-13-late-2015-skylake-core-i5">computershopper</a>, <a href="http://www.expertreviews.co.uk/laptops/ultraportable-laptops/1404207/dell-xps-13-late-2015-review">expertreviews</a>, <a href="http://www.notebookcheck.net/Dell-XPS-13-9350-InfinityEdge-Ultrabook-Review.153376.0.html">notebookcheck</a>), bleeding edge hardware in every sense encompassing 6th generation Intel Skylake processors, NVMe PCIe SSD support, stunning "InfinityEdge" display, ultra lightweight form factor, and a battery life that nears the 10+ hour mark when handling "real world" usage.[^fn-nth-2]

### Dell XPS 13 9350 specifications

With a focus on maximising battery life in tandem with an aversion for touch screen based Ultrabooks I decided to go with a battery conscious hardware configuration; this meant forgoing the very top end i7-6500U CPU and FQHD (3200x1800) "InfinityEdge" display. Another hardware concession that I consciously made was choosing an AHCI based M.2 SATA SSD over Dell's NVMe PCIe SSD option. I made this particular decision with the intention of eventually upgrading the M.2 SSD to a larger sized and better performing NVMe PCIe based SSD (e.g. the <a href="http://www.samsung.com/global/business/semiconductor/minisite/SSD/global/html/ssd950pro/overview.html">512GB Samsung 950 Pro</a>) than Dell's own offering. 

* **CPU**: <a href="http://ark.intel.com/products/88193/Intel-Core-i5-6200U-Processor-3M-Cache-up-to-2_80-GHz">6th Generation Intel(R) Core(TM) i5-6200U</a> 
* **RAM**: 8GB LPDDR3 1866MHz 
* **SSD**: 128GB M.2 Solid State Drive (AHCI)[^fn-nth-3]
* **Display**: 13.3 inch FHD AG (1920 x 1080) InfinityEdge
* **WiFi + Bluetooth Adapter**: DW1820A 2x2 802.11ac 2.4/5GHz + Bluetooth 4.1 (<a href="https://jp.broadcom.com/products/wireless/wireless-lan-infrastructure/bcm4350">Broadcom BCM4350</a>)

## Objectives

* Updating the Dell XPS 13 9350's BIOS to the latest available firmware via a FreeDOS live USB environment.

* The creation and packaging (as a Debian binary archive) of a custom Linux 4.4 kernel that supports <a href="#dell-xps-13-9350-specifications">my Dell 13 9350's hardware</a>.

* The configuration and compilation of a custom Debian Jessie Installer *Hybrid* based ISO with the official `debian-cd` utility. The configuration outlines all the steps taken for adding custom packages/files to the installer ISO from the previously built custom Linux 4.4 kernel Debian binary package and the necessary firmware Debian packages/files which, in combination, result in _complete_ hardware support for <a href="#dell-xps-13-9350-specifications">my Dell 13 9350's hardware</a> upon installation.

* Editing the compiled custom Debian Installer's `initrd.gz` midway through the `debian-cd` process in order to inject a script that runs at the end of the installation process. This is necessary for the Bluetooth firmware file to to be autonomously copied to the correct installation directory.

* Booting the custom made Debian Jessie Installer via USB and outlining the nuances present when installing Debian Jessie 8.3 via the "Expert Installation" option. I've embedded an Asciinema console recording so as to succinctly illustrate these nuances.

* Upon successful installation and subsequent boot from the Dell XPS 13 9350's internal storage I outline the steps required for scanning and connecting to an encrypted (WPA2) WiFi Access Point.

* Invoking `tasksel` for a menu driven, ncurses based "wizard" that assists with installing numerous packages in order to satisfy the selection of user selected high-level "Software Options" (e.g GNOME 3 desktop environment). This menu would have otherwise been present in a traditional Debian Installer that had internet access.

### Rationale

My main intention for creating this custom Debian Installer ISO image in addition to writing this fairly extensive guide was to:

1. Get a better idea on how Debian Installer ISO images were built. Having recently mirrored the entire `amd64` architecture for all "branches" (i.e. stable, testing, and unstable) of Debian I wanted to investigate the feasibility of building up-to-date (and custom) Debian installation media for my virtual environments. 

2. Start my process of giving back to the Debian community and users of the Debian GNU/Linux system with a straightforward installation media that provides an "as expected" standard of functionality in addition to a minimal base installation footprint that I have become used to with Debian.

### Scenarios

> _"I have already installed Debian, I just want all the hardware to work!"_

Take a look at the "_Existing Installation_" link in the <a href="#downloads">Downloads</a> section for obtaining my custom Linux 4.4 kernel and non-free firmware packages. 

> Select the firmware package that corresponds to your WiFi adapter (e.g. `firmware-brcm80211_20160110-1_all.deb` corresponds to the Broadcom BCM4350 chipset).
{: .prompt-info }

Once you have downloaded the Debian binary packages you can go ahead and install them in a standalone fashion (i.e. no dependencies required):
```bash
  sudo dpkg --install *.deb
```

Once all the Debian binary packages have been installed and you have rebooted into the custom Linux 4.4 kernel continue to follow the guide from !!! LINK HERE MYLES !!! section 9 onwards to understand how to connect to an encrypted WiFi AP via the command line.

> Please ensure you have updated the firmware to the latest release! See !!! LINK HERE MYLES !!! step 1 in the guide for how to update the Dell XPS 13 9350's BIOS.
{: .prompt-warning }

<hr>
> _"I'm not interested with how this ISO was made, I just want a straightforward Debian installation that includes all drivers"_

The custom Debian Jessie Installer ISO link can be found in the <a href="#downloads">Downloads</a> section (below) labelled as the "_Fresh Installation_" option.

Once you have downloaded the ISO image you can skip to section 8 !!! LINK HERE MYLES !!! in this post which will walk you through the remainder of the steps required for installing a Debian Jessie 8.3 environment with complete hardware support. 

## Downloads

In an effort to cater to both <a href="#scenarios">scenarios</a> outlined above I have provided two separate download options. Pick one that most suits the scenario you face:  

* **Fresh** Installation: <a href="https://drive.google.com/folderview?id=0B459txgVvoaUTHFUSy02MUZzZm8&usp=sharing">Custom Debian Jessie Installer ISO</a>
* **Existing** Installation: <a href="https://drive.google.com/open?id=0B459txgVvoaUd2NiTjlDSUNTTmc">4.4 Kernel & Firmware Packages</a>

> `md5sum` hashes are included within both the custom Debian Jessie Installer ISO and the Debian binary packages respectively. 
{: .prompt-info }

### Packages Used

* `bzip`: 1.0.6-7+b3
* `binutils`: 2.25-5
* `fakeroot`: 1.20.2-1
* `kernel-package`: 13.014+nmu1
* `libncurses5-dev`: 5.9+20140913-1+b1
* `wget`: 1.16-1
* `debian-cd`: 3.1.17

## BIOS

### Configuring USB booting

> You can skip this section if you have already installed Debian and have the most up-to-date BIOS firmware flashed already. 
{: .prompt-info }

The Dell XPS 13 9350 is no exception to the rule when it comes to the gradual assimilation of UEFI over the legacy BIOS implementation in consumer targeted hardware solutions. As Dell made the (arguably well placed) assumption that the majority of its users would use Microsoft Windows 10, and *only* Microsoft Windows 10, as the bare metal OS a series of UEFI configurations are necessary to permit (i.e. disable <a href="https://en.wikipedia.org/wiki/Hardware_restriction#Secure_boot">Secure Boot</a>) and enable "Legacy" (i.e. MBR driven booting as opposed to a dedicated EFI System Partition) based booting via USB.

1. Turn the Dell XPS 13 9350 on and press the <kbd>F2</kbd> button when presented with the Dell POST logo.
 
2. Navigate to the `Boot Sequence` category (`Settings` --> `General` --> `Boot Sequence`).
    
3. Change the `Boot List Option` to: `legacy`

4. Change the ordering of the `Boot Sequence` so the `USB Storage Device` is the _first_ entry.

5. Navigate to `System Configuration` category (`Settings` --> `System Configuration`).

6. Change the `SATA Operation` to: `AHCI`

7. Disable the "Secure Boot" feature: *Settings* -> *Secure Boot Enable* -> *Secure Boot Enable*: `Disabled`

Now we have performed the necessary UEFI configuration to provide booting from USB we can go ahead and update the BIOS (if not done already) and boot the custom Debian Jessie Installer ISO (if choosing the _fresh_ installation option).

### Updating

The most recent Dell XPS 13 9350 BIOS firmware can be downloaded from the official Dell site <a href="https://www.dell.com/support/home/en-us/product-support/product/xps-13-9350-laptop/drivers">here</a>. 
Be aware that the BIOS seems to be in active development with the current release being at build version 1.2.3 (as of 30/01/2016) despite being at 1.1.9 only just two weeks ago when I initially updated.

As always BIOS updates can fix (but sometimes introduce) various hardware issues while simultaneously improving support for various peripherals (e.g. <a href="http://accessories.dell.com/sna/productdetail.aspx?c=us&l=en&s=dhs&cs=19&sku=450-AEVM">Dell Thunderbolt 3 docks</a>). Consequently I would recommend checking the above Dell XPS 13 9350 BIOS firmware download page on a semi-frequent basis to ensure you are benefiting from the latest firmware enhancements/fixes.

The simplest approach for updating the BIOS is to install the downloaded BIOS firmware executable within a Microsoft Windows OS environment. However, for this guide I take a different update path that alleviates the requirement of a preexisting Microsoft Windows OS environment. Instead I utilise "FreeDOS" which makes it possible for the user to update their Dell XPS 13 9350's BIOS in the situation where they do not have access to the Microsoft Windows OS environment.

> You need to ensure that your Dell XPS 13 9350 can boot from USB. See the <a href="">previous section</a> in the guide for doing this.  
{: .prompt-info }

1. Download a compressed, minimal version of FreeDOS that supports being booted from a USB: 
```bash
wget https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.3/official/FD13-LiteUSB.zip --directory-prefix ~/
```

2. Extract the "zipped" FreeDOS image:
```bash
unzip --decompress ~/FD13-LiteUSB.zip

   # Expected result
Archive:  FD13-LiteUSB.zip
  inflating: FD13LITE.img            
  inflating: FD13LITE.vmdk           
  inflating: readme.txt        
```

3. Write the FreeDOS image to a USB mass storage device:
```bash
sudo dd if=~/FD13LITE.img bs=4M of=/dev/sdX
```
    > Take care ensuring that the `sdX` SCSI device node corresponds to your targeted USB mass storage device.
    {: .prompt-warning }

4. Instruct the kernel to rescan the USB mass storage device to enumerate the single FreeDOS FAT32 based OS partition:
```
echo 1 | sudo tee /sys/block/sdX/device/rescan
```

5. Create a dedicated mount point for the FreeDOS FAT32 based OS partition to copy the latest Dell XPS 13 9350 BIOS firmware executable (`.exe` file) onto it:
```bash
sudo mkdir /mnt/freedos
sudo mount /dev/sdX1 /mnt/freedos
```

6. Download the latest Dell XPS 13 9350 BIOS firmware and save it under the recently mounted `/mnt/freedos/` directory:
```bash
sudo wget https://dl.dell.com/FOLDER06641437M/1/XPS_9350_1.13.0.exe --directory-prefix /mnt/freedos/
```
    > We need to use `sudo` here as the FAT32 based mount point does not permit traditional UNIX privileges and hence only *root* can write to the filesystem.
    {: .prompt-info }

7. Unmount the USB stick and connect it to your powered down Dell XPS 13 9350.

    > Ensure your Dell XPS 13 9350 is connected to AC power source _before_ proceeding
    {: .prompt-warning }

8. When FreeDOS OS boots and presents the "Install" menu select your preferred language and then select: `No - Return to DOS` 

9. Once presented with the FreeDOS shell prompt invoke the BIOS update executable (press the <kbd>Enter</kbd> key):
```bash
C:\FDOS>xps_93~1.exe
```
The command in this step appears odd and I believe its related to the manner in which particular file names are handled by the FreeDOS OS. Press the <kbd>Tab</kbd> key after typing `xps` to automatically populate the correct file name.

10. Once the <a href="https://en.wikipedia.org/wiki/Ncurses">ncurses</a> styled menu appears giving a brief oversight into the operations the BIOS firmware update will involve proceed with update by pressing the <kbd>y</kbd>, <kbd>enter</kbd> keys.

## Firmware

### Obtaining packages

Beside employing the traditional `lscpi -vv` command to get an idea of the hardware neatly arranged inside my Dell XPS 13 9350 I scoured a variety of Linux oriented websites in an effort to identify which kernel drivers were required. 
I've decided to include this section to provide those interested in further configuration and understanding of the kernel drivers employed by Linux for powering their Dell XPS 13 9350.

* <a href="https://wiki.archlinux.org/index.php/Dell_XPS_13_(2016)">Arch Linux Wiki</a>: Outlined the drivers that were tested as functional by the Arch Linux community members. Once I had ascertained the *name* of kernel drivers that worked I set about "Googling" which kernel configuration option they corresponded to.

* <a href="https://wiki.gentoo.org/wiki/Dell_XPS_13_9343">Gentoo Linux Wiki</a>: Despite targeting the  Dell XPS 13 9350's predecessor, the 9343, I found that for the certain hardware components had persisted between the incremental upgrade (e.g. USB controller). From the documentation I was able to get a quick start on the location of the kernel configuration options within the ncurses driven  `make menuconfig` kernel configuration  menu.

* <a href="packages.debian.org">Debian Package explorer</a>: Some hardware required a firmware counterpart in addition to their respective kernel configuration. From here I was able to ensure that the correct firmware file was procured between (e.g. Broadcom Wifi, Intel Skylake microcode, etc.) the various revisions (based on the branch of Debian) of the firmware based Debian binary package. 

   > All firmware based Debian binary packages have been procured from the Sid branch of Debian. Jessie and Stretch versions of the Firmware package did _not_ include the required firmware files.
   {: .prompt-info }
  

## Linux kernel 

### Compiling a custom kernel

With kernel compilations on my server (Octeron) being performed on a regular basis I have become very familiar with the preparation, compilation, and installation process of building custom kernels. I use a distribution agnostic process for compiling and installing kernels which results in a slight management overhead from having to maintain a handful of custom kernels. 

To increase the custom kernel's portability and ease of installation within other Debian GNU/Linux systems I took the decision to adjust my process, in particular the *installation* phase, so as to produce a Debian binary archive (`.deb`) at the end of the overall compilation process. This Debian binary archive could then be easily maintained by the end user's APT environment as it would appear and behave like a typical Debian package.

So as to remain as identical as possible to the authentic Debian distributed kernel's, I took the kernel configuration file (`.config`) from the <a href="https://wiki.debian.org/DebianExperimental">Debian Experimental</a> repository and only appended the driver options that were otherwise missing.
For brevity I have omitted the steps necessary for procuring this configuration file but will happily add them to this section in the guide if requested.

The Broadcom BCM4350 chipset found in my Dell XPS 13 9350 was recently merged into the mainline Linux 4.4 kernel release under the guise of this <a href="http://lxr.free-electrons.com/source/drivers/net/wireless/brcm80211/brcmfmac/pcie.c#L50">patch</a>. Unfortunately this driver requires a closed source firmware binary blob to operate correctly on the Dell XPS 13 9350.

The steps necessary for preparing, compiling, and packaging a custom Linux 4.4 kernel and corresponding kernel headers is as follows. I used the Gentoo wiki for the Dell XPS 13 9343 kernel configuration (<a href="https://wiki.gentoo.org/wiki/Dell_XPS_13_9343">here</a>) as a _guideline_ for ensuring that I had selected the correct `CONFIG_*` options during preparation.

1. Install the packages necessary for compiling a Linux kernel and packaging it in a Debian binary archive format:
```bash
sudo apt-get install binutils fakeroot kernel-package libncursesdev-5 wget
```

2. Create a dedicated build directory for the vanilla Linux 4.4 kernel:
```bash
mkdir ~/linux-source-4.4
```

3. Download and extract the compressed Linux 4.4 kernel source tarball:
```bash
wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.4.tar.xz --directory-prefix ~/linux-source-4.4
                                                                      --output-document - | tar --extract --xz
```

4. Copy the existing kernel configuration file (`.config`) stored within the Debian Experimental package `linux-source-4.4_4.4~rc8-1~exp1_all.deb` to the current directory:
```bash
cp /path/to/extracted/experimental/linux-source/.config ~/linux-source-4.4/linux-4.4/.config
```

5. Configure the kernel to include all necessary drivers for <a href="#dell-xps-13-9350-specifications">my Dell XPS 13 9350's hardware configuration</a>:
```bash
make menuconfig
```

6. Compile the custom kernel and corresponding kernel headers with the Debian utilities for producing two easily installed Debian binary archives:
```bash
   # Optional, utilise all CPU cores + 1
export CONCURRENCY_LEVEL=(( $(nproc) + 1 ))
sudo fakeroot make-kpkg --initrd \
                           --revision=9350 \
                           kernel_image \
                           kernel_headers
```
Once completed the custom Linux 4.4 kernel and corresponding headers can be found in their respective Debian binary package in the build directory's parent directory:  `~/linux-{image,headers}-4.4.0_9350_amd64.deb`
    > Approximately 10GiB of free space was required for this compilation. 
    {: .prompt-warning }

At this stage we have managed to compile and package a custom Linux 4.4 kernel and corresponding kernel headers that supports all the hardware found in my Dell XPS 13 9350. 
By including the kernel headers as part of the custom Debian Installer ISO it has allowed my custom kernel to accept future kernel modules (if desired) to be compiled against it and managed via <a href="https://en.wikipedia.org/wiki/Dynamic_Kernel_Module_Support">DKMS</a>. 

For those interested in the custom 4.4 kernel configuration file (`.config`) used I have uploaded it <a href="https://drive.google.com/folderview?id=0B459txgVvoaUTHFUSy02MUZzZm8&usp=sharing">here</a>. As stated previously: I only made minimal alterations (mainly additions) in an effort to follow the Debian Experimental's Linux image as closely as possible. 

### Customised Linux 4.4 kernel's "control" file

One of the trickiest parts of configuring a custom Debian Jessie installer ISO was understanding how the Debian Installer ascertained what was (and wasn't) an acceptable Linux kernel package. 
After countless hours exploring scripts and reading aborted Debian Installation logs I found that the Debian Jessie Installer `initrd.gz` (examined in greater depth later in this guide) contained the script `/usr/lib/base-installer/kernel.sh` which, after loading installer components from the installation media at run time, would check the packages with their *section* field (as denoted in the Packages.gz file) being listed as _only_ "kernel" to see if they matched the following criteria:
```bash
# /usr/lib/base-installer/kernel.sh
...
arch_check_usable_kernel () {
    case "$1" in
       *-dbg)
           return 1
           ;;
        *-amd64 | *-amd64-*)
           # Allow any other hyphenated suffix
           return 0
           ;;
        *)
           return 1
           ;;
    esac
}
...
``` 
If the kernel package's *name* as listed in the kernel Debian package's <a href="https://www.debian.org/doc/debian-policy/ch-controlfields">control file</a> did _not_ match the `kernel.sh`'s regex filter than that particular kernel would _not_ be listed in the kernel selection menu as part of the installation process.

1. Create and navigate into a dedicated directory for extracting the newly packaged custom Linux 4.4 kernel:
```bash
mkdir ~/custom-kernel
cd ~/custom-kernel
```

2. Move the custom Linux 4.4 kernel Debian binary package into the `~/custom-kernel` directory:
```bash
mv ~/linux-image-4.4.0_9350_amd64.deb ~/custom-kernel
```

3. Extract the custom Linux 4.4 kernel Debian binary package from its _archive_:
```bash
ar r linux-image-4.4.0_9350_amd64.deb
```

4. Create a dedicated directory for the meta-data based _control_ files and navigate into it:
```
mkdir ~/custom-kernel/control
cd ~/custom-kernel/control
```

5. Extract the `control.tar.gz` so we can get access to the custom Linux 4.4 kernel Debian binary package's _control_ file:
```bash
tar --extract \
       --gunzip \
       --file ../control.tar.gz 
```

6. Edit the newly extracted `control` text file and append "-amd64" to the value set in the `Package` field:
```bash
...
Package: linux-image-4.4.0-amd64
...
```

7. Construct a new compressed (gzipped) tarball `control.tar.gz` from all the files present in the current directory:
```bash
tar --create \
       --gzip \
       --file * ../control.tar.gz
```

8. Navigate to the parent directory containing the newly compressed `control.tar.gz` tarball and other _untouched_ Debian package components (e.g. `data.tar.xz`, `debian-binary`):
```bash
cd ~/custom-kernel
```

9. Repackage the custom Linux 4.4 kernel Debian binary archive:
```bash
ar r linux-image-4.4.0_9350_amd64.deb debian-binary control.tar.gz data.tar.xz
```
    > The order here (i.e. `debian-binary` _first_) of files to be included in the *archive* is critical! 
    {: .prompt-info }

10. Move the altered custom Linux 4.4 Debian binary package to the directory designated in the previous section:
```bash
mv ~/custom-kernel/linux-image-4.4.0_9350_amd64.deb /path/to/my/custom/debs
```

I found that the custom Linux 4.4 kernel headers' _control_ file did _not_ list the originally named `linux-image-4.4.0` package as a *Dependency* so would _not_ need to be altered to correctly reference the renamed custom Linux 4.4 kernel package. 
For consistency purposes I decided to suffix the kernel headers' _control_ file _Package_ name with "-amd64". I followed an almost identical process to the above steps for making this change and have consequently omitted these repetitive steps here.
 
## Debian Jessie Installer

### Customised ISO build

The `debian-cd` package is a collection of scripts used by the Debian CD <a href="https://wiki.debian.org/Teams/DebianCd">team</a> for the production of the official and daily/weekly Debian Installer CD/DVD images. In addition to the package being available in the "main" repository (<a href="https://packages.debian.org/jessie/debian-cd">here</a>) for the latest Git development branch can be cloned (<a href="https://alioth.debian.org/anonscm/git/debian-cd/debian-cd.git/">here</a>).
 
Despite having read the `debian-cd`'s supplied README on several occasions I faced a variety of undocumented hurdles when attempting to include my own set of custom packages in my custom Debian Jessie installer ISO. Moreover I encountered further challenges when trying to include my own custom scripts for automating the copying of the Bluetooth firmware file.
I've outlined these various difficulties throughout this section as well as the following section in the hope they assist others who wish to alter the Debian Installer image in a similar fashion.

1. Install the `debian-cd` package required for constructing a Debian Jessie Installer ISO image in addition to the `dpkg-dev` package which provides the `dpkg-scanpackages` helper utility for generating Package lists:
```bash
sudo apt-get install debian-cd dpkg-dev
```

2. Create a dedicated directory for copying the `debian-cd` package contents (scripts, configuration files, READMEs, etc) to:
```bash
mkdir ~/debian-cd
cp --recursive /usr/share/debian-cd ~/debian-cd
```

3. Alter the ownership of the copied `debian-cd` files to the current user:
```bash
sudo chown --recursive $USER:$USER ~/debian-cd
```

4. Create the required `debian-cd` dedicated build directories on the _same_ partition as that of the locally stored Debian mirror. In addition to this create a dedicated "custom" directory that will store our custom Debian packages:
```bash
mkdir --parents /mnt/archive/dell/{tmp,apt-tmp,images,custom}
```

5. Create the required directory structure for correctly adding custom packages during the Debian Jessie Installer ISO creation:
```bash
mkdir --parents /mnt/archive/dell/custom/dists/jessie/local/binary-amd64
```
Where `jessie` and `binary-amd64` have been substituted in from their variable alias `$CODENAME` and `$ARCH` respectively.

6. Copy the custom Linux 4.4 kernel and headers as well as all the firmware packages into the directory created in the previous step:
```bash
cp /path/to/my/custom/debs/* /mnt/archive/dell/custom/dists/jessie/local/binary-amd64
```
I have listed these custom and firmware based packages in the previous *section* of this guide.

7. Generate a _Package list_ of the custom and firmware based packages in a format that can be consumed by the `debian-cd` script suite:
```bash
dpkg-scanpackages /mnt/archive/dell/custom | gzip --stdout --best > /mnt/archive/dell/custom/dists/jessie/local/binary-amd64/Packages.gz`
```
By invoking the `dpkg-scanpackages` utility at the `/mnt/archive/dell/custom/` directory depth we ensure that each package's _path_ value is of a valid relative URI for ensuring a correct lookup when the Debian Installer attempts to install the package. E.g.: `/dists/jessie/local/binary-amd64/firmware-brcm80211_20160110-1_all.deb`

8. Navigate to the `~/debian-cd` directory created previously:
```bash
cd ~/debian-cd
```

9. Edit the previously copied `debian-cd` global configuration file `CONF.sh` file and adjust the following values:
```bash
export BASEDIR=`pwd`
export CDNAME=debian
export CODENAME=jessie
# Important to use the corresponding distributions d-i otherwise kernel ABI breakages!
# 'current' just points to the latest d-i build (vmlinuz & intird.gz pair) available for Jessie
export DI_WWW_HOME=http://10.0.1.254/debian/dists/jessie/main/installer-amd64/current/images
export DEBVERSION="8.3.0"
export MIRROR=/mnt/archive/mirrors/debian
export TDIR=/mnt/archive/dell/temp
export OUT=/mnt/archive/dell/images
export APTTMP=/mnt/archive/dell/apt-temp
# Firmware packages don't get added otherwise...
export FORCE_FIRMWARE=1
export LOCAL=1
export LOCALDEBS=/mnt/archive/dell/custom
export amd64_MKISOFS="xorriso"
export amd64_MKISOFS_OPTS="-as mkisofs -r -checksum_algorithm_iso md5,sha1"
export ARCHIVE_KEYRING_PACKAGE=debian-archive-keyring
export ARCHIVE_KEYRING_FILE=usr/share/keyrings/debian-archive-keyring.gpg
export DEBOOTSTRAP_OPTS="--keyring $TDIR/archive-keyring/$ARCHIVE_KEYRING_FILE"
export ISOLINUX=1
export DISKTYPE=NETINST
export IMAGESUMS=1
# Path to file listing additional main & custom packages for inclusion
export BASE_INCLUDE="$BASEDIR"/data/$CODENAME/base_include
export INSTALLER_CD=2
export TASK=debian-installer+kernel
export MAXCDS=1
# Saving disk space
export OMIT_MANUAL=1
export OMIT_RELEASE_NOTES=1
```

10. Append the targeted packages to be included in the custom Debian Jessie Installer ISO image to the `~/debian-cd/data/jessie/base_include` file:
```bash
wpasupplicant
iw
wireless-tools
tasksel
firmware-brcm80211
firmware-iwlwifi
firmware-misc-nonfree
```
    > The omission of both the `linux-image-4.4.0-amd64` and `linux-headers-4.4.0-amd64` packages is on _purpose_ at this stage. From my own testing I found that including the custom Linux 4.4 kernel as part of the `~/debian-cd/data/jessie/base_include` file seems to confuse the Debian Installer and results in a failed installation.
    {: .prompt-info }

11. Source the modified `CONF.sh` configuration file into the shell's current session:
```bash
source CONF.sh
```

12. Clean the build environment as recommended by the `debian-cd` process:
```bash
make distclean
```

13. Initialise the temporary directory used for the build by `debian-cd`:
```bash
make status
```

14. Edit the `debian-cd` `TASK` file, `/mnt/archive/dell/tmp/jessie/tasks/debian-installer+kernel`, in the designated `TDIR` build directory (`/mnt/archive/dell/temp/`) to replace the stock kernel with our custom Linux 4.4 kernel. 
```bash
...
#ifdef ARCH_amd64
initramfs-tools
busybox
grub-legacy
grub-pc
grub-efi
grub-efi-amd64
grub-efi-amd64-bin
laptop-detect
lilo
linux-image-4.4.0-amd64
linux-headers-4.4.0-amd64
#endif
...
```

15. Specify the list of extraneous (i.e. optional) packages targeted for inclusion on the custom installer. Typically you would pass the `TASK` and `COMPLETE` values as flags to the `make packagelists` invocation however this is unnecessary given their assignments in the `CONF.sh` file:
```bash
make packagelists
```

16. Render the complete list of packages and respective dependencies targeted by the desired `TASK`: 
```bash
make image-trees
```

17. Unfortunately the Bluetooth firmware file is not part of an existing Debian binary package consequently will need to be manually included into the Debian Jessie Installer ISO:
```bash
cp /path/to/firmware/BCM-0a5c-6412.hcd /mnt/archive/dell/tmp/jessie/CD1/firmware
chown grindon:grindon /mnt/archive/dell/tmp/jessie/CD1/firmware/BCM-0a5c-6412.hcd
chmod 644 /mnt/archive/dell/tmp/jessie/CD1/firmware/BCM-0a5c-6412.hcd
```
This Bluetooth firmware file is intended to be copied autonomously by the Debian Installer to the target installation's directory: `/target/lib/firmware/brcm/BCM-0a5c-6412.hcd` so as to be loaded automatically at boot. Adjusting the ownership and permissions ensures the firmware is correctly injected into the customised installer.

> Converting the Microsoft Windows Bluetooth driver (for the BCM4350 Bluetooth 4.1 + WiFi adapter) to a Linux compatible driver is performed via the `hex2hcd` utility. For those interested the Arch Linux wiki outlines the steps and utilities involved for performing this conversion (<a href="https://wiki.archlinux.org/index.php/Dell_XPS_13_(2016)#Bluetooth">here</a>).
{: .prompt-tip }


### Customised installer initramfs

The manner in which the ISO is booted (UEFI or MBR) will determine which bootloader (Syslinux or GRUB2) is loaded by the Debian Installer (<a href="https://wiki.debian.org/UEFI#How_to_tell_if_you.27ve_booted_via_UEFI">source</a>). The underlying booting mechanism influences other aspects of the Debian installer (e.g. partition configuration, GRUB installation) to ensure a functional installation of a GNU/Linux Debian system. 

All scripts used by the Debian Jessie installer are located within the `initrd.gz` for both the <a href="https://en.wikipedia.org/wiki/GTK">GTK</a> (Graphical) and <a href="https://en.wikipedia.org/wiki/Ncurses">ncurses</a> (Expert/Rescue/Automated) boot options. For automating the copying of the Bluetooth firmware file, `BCM-0a5c-6412.hcd`, we need to include a custom script ("Hook") that will run at the end of the installation. To achieve this we must decompress and extract the CPIO based archive (`initrd.gz`), insert the custom script in the correct directory, generate a new CPIO archive, compress (`gzip`) the new CPIO archive, and finally replace the _Expert Installation_ option's `initrd.gz`.  
For those interested, the official documentation for the Debian Installer processes/components _within_ the `initrd.gz` can be found <a href="http://d-i.alioth.debian.org/doc/internals/ch02.html">here</a>.

Identifying which kernel and initrd pair the _Expert Install_ option uses when booting via UEFI can be identified by examining the `/mnt/archive/dell/tmp/jessie/CD1/boot/grub/grub.cfg` configuration file:
```bash
...
menuentry '... Expert install' {
    set background_color=black
    linux    /install.amd/vmlinuz priority=low vga=788 --- 
    initrd   /install.amd/initrd.gz
}
...
```

1. Create a dedicated directory for the "Expert Installation" option's `initrd.gz` and copy the `initrd.gz` file to it:
```bash
mkdir ~/custom-initrd
cp /mnt/archive/dell/tmp/jessie/CD1/install.amd/initrd.gz ~/custom-initrd
```

2. Extract the gzipped CPIO archive:
```bash
gunzip ~/custom-initrd/initrd.gz
```

3. Create another directory that will store the contents of the extracted CPIO archive and navigate into it:
```bash
mkdir ~/custom-initrd/extracted
cd ~/custom-initrd/extracted
```

4. Extract the CPIO archive within the `fakeroot` utility wrapper (required to isolate the `mknod` syscalls made by extracting the CPIO archive):
```bash
fakeroot cpio --make-directories \
                 --extract < ../initrd
```

5. Create the custom script for installing the Bluetooth firmware file, `~/custom-initrd/extracted/usr/lib/finish-install.d/14bcm4350-bluetooth`:
```bash
   #! /bin/sh -e

   # Copying the BCM4350 Bluetooth hcd firmware file to the install target
cp /cdrom/firmware/BCM-0a5c-6412.hcd /target/lib/firmware/brcm/BCM-0a5c-6412.hcd
```

6. Set executable permissions on the `14bcm4350-bluetooth` script:
```bash
chmod 755 ~/custom-initrd/extracted/usr/lib/finish-install.d/14bcm4350-bluetooth
```

7. Regenerate the CPIO archive ensuring to use the `newc` format:
```bash
find ~/custom-initd/extracted | cpio --create --format='newc' > ~/custom-initrd/initrd
```

8. Compress (via `gzip`) the new `initrd` CPIO archive and replace it with the original one located in the previously built ISO:
```bash
gzip --stdout --best ~/custom-initrd/initrd > /mnt/archive/dell/tmp/jessie/CD1/install.amd/initrd.gz
```

9. Regenerate the `md5sum` hashes for all the Debian Jessie Installer files:
```bash
find /mnt/archive/dell/tmp/jessie/CD1/ -type f -exec md5sum {} \; > /mnt/archive/dell/tmp/jessie/CD1/md5sum.txt
```

10. Navigate back to the `~/debian-cd` and commence the final stage of the `debian-cd` process to produce the customised Debian installer ISO image:
```bash
cd ~/debian-cd
make images
```

### ISO usage

The resulting custom Debian Jessie Installer Hybrid ISO image totals in at 228 MiB in size. Therefore any USB mass storage device that is 256 MB (244 MiB) or bigger in capacity will be able to hold the ISO image.
> Ensure you backup any data from your chosen USB mass storage device as the following operations will wipe any existing partition tables and partition structures.  
{: .prompt-warning }

1. Write the Hybrid ISO image to the targeted USB mass storage device:
```bash
sudo dd if=/mnt/archive/dell/images/debian-8.3.0-amd64-NETINST-1.iso/ bs=1M of=/dev/sdX
```
    > Where `X` is the letter of the targeted SCSI based USB mass storage device. Make sure you double check this letter!
    {: .prompt-danger }

2. Turn the Dell XPS 13 9350 on and press the <kbd>F2</kbd> button when presented with the Dell POST logo.
 
3. Navigate to the "Boot Sequence" category: *Settings* -> *General* -> *Boot Sequence*

4. Change the "Boot List Option" to: `UEFI`

5. Save configuration by selecting the <kbd>Apply</kbd> button and selecting the <kbd>OK</kbd> button in the _Apply Settings Confirmation_ prompt window.

6. Plug the imaged USB mass storage device into your Dell XPS 13 9350.

7. Select the <kbd>Exit</kbd> button which should result in the Dell XPS 13 9350 restarting itself.

8. When presented with the Dell POST logo Press <kbd>f12</kbd> to select the one-time _Boot Options_ menu.

9. Select the USB mass storage device under the `UEFI BOOT` submenu.

10. Once operating within the <a href="https://wiki.syslinux.org/wiki/index.php?title=SYSLINUX">SYSLINUX</a> menu interface navigate to "Expert Install": _Advanced Boot Options_ -> _Expert Install_.

    > Do _not_ choose the Graphic Installation option as this does not utilise the custom `initrd.gz` I altered for autonomously copying the Bluetooth firmware to the target installation directory.
    {: .prompt-warning }

To avoid having to outline every installation step that diverts from a traditional Debian installation process I've embedded an Asciinema recording below of me performing the installation steps from within a UEFI enabled KVM VM.

> If you cannot see the embedded player below please follow this direct link: <a href="https://asciinema.org/a/c4gm89ivws4pbymzdsw8rkg7n">here</a>
{: .prompt-tip }

<script type="text/javascript" src="https://asciinema.org/a/c4gm89ivws4pbymzdsw8rkg7n.js" id="asciicast-c4gm89ivws4pbymzdsw8rkg7n" async></script>

- I enabled the Debian backports to ensure software such as `Xorg` included the required up-to-date Intel graphical drivers for a windowed environment.  

Upon restart press the <kbd>F2</kbd> button when presented with the Dell POST logo. Once you have entered the BIOS configuration screen ensure that a UEFI entry has been made for `debian` and is selected as the top option. If the entry does _not_ exist the installation has not prepared GRUB correctly or the custom Debian Jessie Installer was booted via `MBR` as opposed to `UEFI`. 

### Post-installation configurations

If upon rebooting you have had the GRUB2 bootloader appear correctly after POST, had the custom Linux 4.4.0 kernel boot without issue, and finally been presented with a blinking login shell the core Debian Jessie 8.3 system has now been correctly installed.

The final following steps outline, as mentioned previously, connecting to an encrypted (WPA2 Personal) wireless access point and running the `tasksel` utility to simplify installing a particular desktop environment.

1. Login to the Dell XPS 13 9350's Debian Jessie 8.3 environment as the `root` user with the password set during the Debian installer.

2. Enable the Dell XPS 13 9350's WiFi interface `wlan0`: 
```bash
sudo ip link set dev wlan0 up
```

3. Scan for your targeted Encrypted Access Point SSID:
```bash
sudo iw wlan0 scan | grep SSID
```

4. Generate a WPA PSK from an ASCII passphrase for the targeted SSID:
```bash
wpa_passphrase "${SSID_NAME}" > /home/$USER_NAME/ssid_psk.key
```
    * Type the password/passphrase on the empty new line when prompted. Once completed hit [enter] and the passphrase will be committed to the file in its PSK hash format.  

5. Alter permissions of the newly generated `ssid_psk.key` file:
```bash
chmod 600 /home/$USER_NAME/ssid_psk.key
```

6. Connect to the WPA PSK encrypted access point ensuring to use the `ssid_psk.key` key:
```bash
wpa_supplicant -B -D wext -c /home/$USER_NAME/ssid_psk.key -i wlan0
```

7. Confirm that their is a "link level" connection between the Dell XPS 13 9350 and the targeted encrypted wireless access point:
```bash
iw wlan0 link

   # Example Result: 
Connected to 01:23:45:67:89:0A (on wlan0)
        SSID: Asus RT-N56U 5Ghz
        freq: 5180
        RX: 342 bytes (2 packets)
        TX: 800 bytes (8 packets)
        signal: -45dBm
        tx bitrate: 24.0MBit/s

        bss flags:
        dtim period:    1
        beacon int:     100
```

8. Obtain an IP address from the encrypted wireless access point's internal DHCP server:
```bash
dhclient -v wlan0
```
    * This operation will also set the Dell XPS 13 9350's DNS settings (assuming the DHCP server provides `option domain-name-servers` values). Client DNS configuration can be viewed from the dynamically generated `/etc/resolv.conf` file.

9. Uncomment the Debian Jessie-{Update,Backport} repository URLs, append the 'contrib' option to both repositories, and create a new entry that corresponds to the base directory for the "Jessie" packages:  
```bash
   # /etc/apt/sources.list
deb http://ftp.debian.org/debian/ jessie main non-free contrib
deb http://ftp.debian.org/debian/ jessie-updates main non-free contrib
deb http://ftp.debian.org/debian/ jessie-backports main non-free contrib
```

10. Update the local APT package cache to acknowledge these repository additions: 
```bash
apt-get update
```

11. Run the `tasksel` utility and select the desired desktop environment:
```bash
tasksel --new-install
```

### Final Words

As indicated previously, I am planning to compile a _minimal_ custom Linux kernel that would provide support for all hardware configurations of the Dell XPS 13 9350. As I have done with the custom Linux 4.4 kernel compiled in this guide I will generate the corresponding Debian binary archive for both the kernel and its respective headers to permit the compilation of additional kernel modules.

Having now *painlessly* installed a minimal Debian environment with complete hardware support my next "adventure" will be to investigate the numerous power saving adjustments that can be made in order to maximise battery life. 

---

[^footnote]: Its still lives to this day as a headless Debian Jessie server but the GPU gives out when attempting to run an X11 environment. Given that *Octeron* handles all my virtualisation requirements the Dell Studio 1558 operates as an overpowered DNS server - I'd feel sorry for it had it not died in the middle of my writing my BSci dissertation...

[^fn-nth-2]: After applying all known power configurations options!

[^fn-nth-3]: I have included NVMe PCIe kernel modules in addition to the drivers for the Intel WiFi but as I have not tested it I cannot confirm its functional.

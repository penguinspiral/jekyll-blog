---
title: Generating and distributing entropy with the OneRNG HWRNG USB in various virtualisation environments
date: '2017-08-06 08:46:42'
categories: [Virtualisation]
tags: [OneRNG, HWRNG, entropy]
---

Part of the provisioning process for the VPS host in which this Ghost blog platform originally ran atop involved the generation of a 4096-bit GPG key pair. Exporting, transferring, importing, and ultimately signing the GPG public keys between my laptop and the VPS established the "trust" necessary for strong asymmetric encryption. This encryption mechanism provided the necessary foundation for securely employing the "Single Packet Authentication" utility, <a href="https://www.cipherdyne.org/fwknop/">fwknop</a>, for which I use in addition to SSH public key authentication for accessing my VPS.
It was during the generation of the GPG keys on the VPS that I witnessed the severe extent in which traditional hardware virtualised machines (HVM) struggle to generate entropy.

## Intro

The _painfully_ slow rate in which a HVM generates entropy arises from a reduced amount of available "environment noise" that traditional <u>physical</u> hardware inputs provide as a desirable side effect to their general usage. As per the Linux Kernel's (4.12-rc6) `random.c` <a html="http://elixir.free-electrons.com/linux/v4.12-rc6/source/drivers/char/random.c">source file</a>, these "inputs" refer to:
> "_[...] inter-keyboard timings, inter-interrupt timings from some interrupts, and other events which are both (a) non-deterministic and (b) hard for an outside observer to measure._"

Newer generations of the x86 processors produced by both Intel (IvyBridge and onwards) and AMD (post 2015) include the `RdRand` instruction which is "seeded" by an on-chip entropy source (<a html="http://software.intel.com/sites/default/files/m/d/4/1/d/8/441_Intel_R__DRNG_Software_Implementation_Guide_final_Aug7.pdf">source</a>). Sadly my server's AMD Opteron 4386 chip (released late 2012) does not have this particular x86 instruction resulting in prologned delays (similar to that faced with my VPS) when applications consume data from the blocking, cryptographically secure pseudorandom number generator character device node `/dev/random`.
   
Being dissatisfied with the speed in which certain operations/utilities consuming random data from `/dev/random` operated, I began looking into acquiring an affordable, open source based (software _and_ hardware) USB HWRNG (HardWare Random Number Generator). With these constraints in mind I discovered a small open source hardware vendor, <a html="http://www.moonbaseotago.com/">Moonbase Otago</a>, produced their own Linux & GPLv3 friendly HWRNG/entropy source USB device: <a html="http://onerng.info/">OneRNG</a>.

The various virtualisation environments (e.g. LXC, KVM, QEMU) I interact with on a regular basis have their own respective way(s) of interfacing with the OneRNG HWRNG USB device. This post covers the configuration options necessary for obtaining entropy sourced from the underlying host's OneRNG HWRNG USB for consumption by applications within their respective virtual environment.

Beyond virtualisation platform configuration setups I have also included the steps necessary for provisioning a basic, client-server modeled entropy broker/distributor service that leverages the OneRNG HWRNG USB. Such a deployment (inspired from a <a html="https://lwn.net/Articles/546428/">LWN post</a>) allows a _single_ server to distribute entropy (obtained from the OneRNG HWRNG USB) to multiple clients over a TCP/IP network.  

### Prerequisites

1. A OneRNG HWRNG USB device connected to a USB port which has been correctly identified by the Linux kernel ( vendor & device ID: `1d50:6086`): 
```bash
$ dmesg
...
usb 4-1: USB disconnect, device number 2
usb 4-1: new full-speed USB device number 3 using ohci-pci
usb 4-1: New USB device found, idVendor=1d50, idProduct=6086
usb 4-1: New USB device strings: Mfr=1, Product=3, SerialNumber=3
usb 4-1: Product: 00
usb 4-1: Manufacturer: Moonbase Otago http://www.moonbaseotago.com/random
usb 4-1: SerialNumber: 00
```
    {: .nolineno }

2. The _Communication Device Class_ (CDC) _Abstract Control Model_ (ACM) driver (`cdc_acm`) is present either in-kernel or has been dynamically loaded as a kernel module. The OneRNG HWRNG USB is exposed as a TTY ACM character device node (`/dev/ttyACM$`):
```bash
$ dmesg
...
cdc_acm 2-1:1.0: This device cannot do calls on its own. It is not a modem.
cdc_acm 2-1:1.0: ttyACM0: USB ACM device
usbcore: registered new interface driver cdc_acm
cdc_acm: USB Abstract Control Model driver for USB modems and ISDN adapters
...
```
    {: .nolineno }
```bash
$ lsmod | grep cdc_acm
cdc_acm         30362  3 
usbcore        195468  4 uhci_hcd,ehci_hcd,ehci_pci,cdc_acm
```
    {: .nolineno }
```bash
$ ls /sys/devices/pci0000:00/0000:00:03.0/usb2/2-1/2-1:1.0/tty
ttyACM0
grindon@octeron:~$ stat /dev/ttyACM0
File: '/dev/ttyACM0'
  Size: 0       Blocks: 0       IO Block: 4096   character special file
Device: 5h/5d	Inode: 10402    Links: 1    Device type: a6,0
Access: (0600/crw-------)  Uid: (0/root)   Gid: (0/root)
...
```
    {: .nolineno }

### Packages

* `linux-image-amd64`: 3.16+63
* `rng-tools`: 2-unofficial-mt.14-1
* `at`: 3.1.16-1
* `python-gnupg`: 0.3.6-1
* `openssl`: 1.0.1t-1+deb8u6
* `onerng`: 3.5-2
* `lxc`: 1:1.0.6-6+deb8u6
* `qemu-kvm`: 1:2.8+dfsg-6

## Baremetal

While running directly on a host (i.e. "baremetal") is not _strictly_ classified as a "virtualised" environment I felt this particular section was warranted for outlining advanced interactions, service oddities, and troubleshooting steps with the OneRNG HWRNG USB (beyond what is provided in the <a href="http://onerng.info/onerng/">official documentation</a>).

### OneRNG service oddities

* The OneRNG service does not follow the conventional means of service/daemon control management through either a `SysVinit` init.d script or a `systemd` service file.

* The OneRNG service initialisation script, `/sbin/onerng.sh`, is invoked via a `udev` rule, `/lib/udev/rules.d/79-onerng.rules`, when the OneRNG HWRNG USB is detected by the Linux kernel (ID: `1d50:6086`). 

    * The reason for using `udev` over traditional service files/scripts is that `udev` can provide the corresponding chracter device node of the detected OneRNG HWRNG USB, e.g. `ttyACM$`. This _appears_ intended to handle cases whereby an arbitrary amount of `ttyACM$`'s have already been enumerated by the running system.

    * The `/sbin/onerng.sh` acknowledges that `udev` should not be be used for invoking long-running services and so employs the `at` command in conjunction with an `echo` command to re-run the `/sbin/onerng.sh` script with the appropriate arguments (obtained from first invocation via `udev`).

* The `/sbin/onerng.sh` script explicitly disables the `rng-tools` daemon/service and instead invokes it *manually* with arguments determined from configuration options set in OneRNG's global configuration file: `/etc/onerng.conf`. 

* Rather worryingly the `/sbin/onerng.sh` contains `systemd` commands (e.g. `systemctl`) but does not have `systemd` listed as a dependency in the appropriate Debian binary archive `control` file.

### Installation & Verification

1. Update the APT package cache to ensure that we have the latest packages list and their correct remote location:
```bash
sudo apt-get update
```
    {: .nolineno }

2. Install the necessary package dependencies in preparation for installing the individual OneRNG Debian binary archive:
```bash
sudo apt-get install --yes rng-tools at python-gnupg openssl ca-certificates
```
    {: .nolineno }


3. Download the OneRNG Debian binary archive and save it to the current user's `/home` directory:
```bash
wget http://moonbaseotago.com/onerng/onerng_3.5-1_all.deb --directory-prefix=~
```
    {: .nolineno }

4. Install the OneRNG Debian binary archive:
```bash
sudo dpkg --install onerng_3.5-1_all.deb
```
    {: .nolineno }

5. Confirm the OneRNG Debian binary archive has been correctly installed by `dpkg`. The `onerng` package entry should be prefixed by `ii` translating to: _desired_ state = installed, and _actual_ state = installed :
```bash
dpkg --list onerng | tail --lines 1
```
    {: .nolineno }

6. Confirm the OneRNG service is operational by determining whether the leveraged `rngd` daemon is running and pointing to the correct `ttyACM$` device:
```bash
ps aux | grep rngd
```
    {: .nolineno }

7. Confirm the `rngd` daemon is feeding the Linux kernel's entropy pool from data provided by the OneRNG USB:
```bash
cat /proc/sys/kernel/random/entropy_avail
```
    {: .nolineno }
The above command should return a single value in the excess of 1000; such a value indicates that entropy pool is being filled correctly by the `rngd` daemon and OneRNG HWRNG USB.

8. Verify the quality of the randomness produced via the OneRNG HWRNG USB passes the _Federal Information Processing Standard_ publication 140-2 (<a href="https://en.wikipedia.org/wiki/FIPS_140-2">FIPS 140-2</a>) cryptographic standard:
```bash
sudo cat /dev/ttyACM$ | rngtest --blockcount=100 |& grep 'failures\|successes'`
```
    {: .nolineno }
For those wondering why the final pipe of the above command is `|&` as opposed to a single `|`: This is due to the fact `rngtest` outputs to `STDERR` instead of `STDOUT` and a traditional pipe (`|`) will not pass `STDERR` output through to the following command.

### Altering OneRNG States

During my dissection of the `/sbin/onenrng.sh` OneRNG script I encountered the "core" commands used to directly interact (as opposed to via `rngd` daemon) with the OneRNG HWRNG USB character device node. 
As the command "modes" (i.e. the manner in which the OneRNG HWRNG USB generates entropy) are explained in the OneRNG's configuration file (`/etc/onerng.conf`), this subsection examines the omitted - but utilised commands as they may provide useful during testing/debugging/troubleshooting sessions.

1. Power down the OneRNG HWRNG USB:
```bash
echo 'cmdo' | sudo tee /dev/ttyACM$
```
    {: .nolineno }
This operation should result in the entropy pool (`/proc/sys/kernel/random/entropy_avail`) drain until reaching levels prior to connecting the the OneRNG HWRNG USB.

2. Power up the OneRNG HWRNG USB:
```bash
echo 'cmdO' | sudo tee /dev/ttyACM$
```
    {: .nolineno }
This operation should result in the entropy pool (`/proc/sys/kernel/random/entropy_avail`) rapidly filling up again as the OneRNG HWRNG USB can once again feed the `rngd` daemon. Note: The entropy pool value will fill up to the maximum amount specified in `/proc/sys/kernel/random/poolsize`.

3. Flush the current OneRNG HWRNG USB's on-board entropy pool:
```bash
echo 'cmdw' | sudo tee /dev/ttyACM$
```
    {: .nolineno }

### Troubleshooting

> "_The `rngd` service is not reading from the OneRNG `ttyACM$` device node..._"

As covered previously in the <a href="#onerng-service-oddities">Service Oddities"</a> section: the `rngd` daemon is not started at boot by systemd, instead it is invoked via the `/sbin/onerng.sh` script which is turn triggered by a specific `udev` event. While the `/sbin/onerng.sh` script _should_ manually stop the `rngd` daemon I'd argue that explicitly disabling the `rngd` daemon via systemd prevents confusion for why the daemon is running in the first place as well as ensuring the manually invoked `rngd` daemon is the only one running:
```bash
sudo systemctl stop rng-tools
sudo systemctl disable rng-tools
sudo systemctl mask rng-tools
```
{: .nolineno }
<hr>
> "_The `rngd` service is not running at boot or when I plug the OneRNG HWRNG USB in..._"

Open the `/sbin/onerng.sh` script up in an editor and insert `set -x` on its own line immediately under the shebang (`#!`) and save the file. From there invoke the script in the same manner that the `at` command does (ensuring to pass the correct `ttyACM$` device node) and examine the verbose output to begin triaging the issue:
```bash
sudo /sbin/onerng.sh daemon ttyACM$
```
{: .nolineno }
<hr>
> "_Manually invoking the `/sbin/onerng.sh` returns 1 (failure) but the script appears to execute correctly..._" 

If you have enabled the `ONERNG_VERIFY_FIRMWARE` option (default is _enabled_) in the `/etc/onerng.conf` OneRNG configuration file than part of the `/sbin/onerng.sh` will invoke a python script `/sbin/onerng_verify.py` that verifies the integrity of the loaded firmware based off a small contents dump directly from the OneRNG `/dev/ttyACM$` device node. This python script logs all output to `/var/log/syslog` so examining the log contents can help with determining whether the OneRNG firmware has been compromised.
```bash 
echo 'cmdO' | sudo tee /dev/ttyACM$
echo 'cmd0' | sudo tee /dev/ttyACM$
sudo dd if=/dev/ttyACM$ iflag=fullblock bs=512 count=4 of=/tmp/onerng_dump.bin`
sudo /sbin/onerng_verify.py /tmp/onerng_dump.bin
```
{: .nolineno }
The `set -x` flag won't expose the STDOUT of the `/sbin/onerng\_verify.py` python script so manually invoke it against some raw binary data extracted from the OneRNG HWRNG USB so as to examine the verification results:

## KVM

Linux's <a href="https://en.wikipedia.org/wiki/Kernel-based_Virtual_Machine">Kernel-based Virtual Machine</a> (KVM) module provides the hardware accelerated virtualisation foundation that powers not only my VPS host but also all HVM/PVM VM environments on my server ("Octeron"). From reading various QEMU/KVM `man` pages there appears to be two distinct approaches for providing entropy to KVM _guests_ (accelerated or emulated) from the underlying baremetal host: 

1. Through the paravirtualised interface `VirtIO RNG` 

2. Passing the OneRNG HWRNG USB through into the KVM guest and running the OneRNG service as you would on a baremetal host 

Thankfully both methods have been supported since 2009 (<a html="http://wiki.qemu.org/Features/VirtIORNG">source ~ VirtIO RNG</a>, <a html="http://git.qemu.org/?p=qemu.git;a=search;h=HEAD;pg=12;s=USB;st=commit">source ~ QEMU USB Passthrough</a>) making either approach a viable solution for even dated Debian GNU/Linux 6.0 "Squeeze" *guests*! For simplicity the aforementioned approaches are executed against fully supported (in the context of the two entropy approaches), hardware accelerated Debian GNU/Linux 8.0 "Jessie" KVM _guest_. 

### VirtIO RNG

The Fedora feature documentation succinctly summarises the <a href="https://en.wikipedia.org/wiki/Paravirtualization">paravirtualised</a> `VirtIO RNG` interface as: 

> "_[...] a paravirtualized device that is exposed as a hardware RNG device to the guest. On the host side, it can be wired up to one of several sources of entropy, including a real hardware RNG device as well as the host's `/dev/random`_" (<a html="http://wiki.qemu.org/Features/VirtIORNG">source</a>)

Unlike the generic USB passthrough approach, the paravirtualised `VirtIO RNG` interface can be exposed to multiple KVM _guests_ whilst simultaneously applying user-configured, per-guest rate limiting on the consumption of the KVM host's entropy pool. Its flexibility over the alternative option in this regard makes it a favourable solution, however it does require that the KVM _guest_ support the `VirtIO RNG` interface in order for it to be utilised. 

This section outlines the operations necessary for a preconfigured OneRNG HWRNG USB to provide entropy from the KVM _host_ to a KVM _guest_.

#### KVM _host_

1. Check that the OneRNG service is installed correctly and is currently "feeding" the entropy pool of the baremetal KVM host via the `/dev/ttyACM$` character device node. Refer to the <a href="#baremetal">Baremetal</a> section (above) for the setting up the OneRNG HWRNG USB on a Debian GNU/Linux 8.0 "Jessie" systems.

2. Ensure KVM _guests_ targeted for being "fed" entropy over the VirtIO RNG paravirtualised interface have been passed the correct arguments: 
```bash
   # Libvirt 'virt-install'
--rng rate_bytes=$BYTES,rate_period=$MILLISECONDS /dev/random

   # QEMU `qemu-system-x86_64`
-object rng-random,id=rng0,filename=/dev/random,id=rng0 \
-device virtio-rng-pci,rng=rng0,max-bytes=$BYTES,period=$MILLISECONDS \
```
    {: .nolineno }
> It _may_ be possible to specify the random input source to `/dev/ttyACM$` as opposed to the `/dev/random` device node specified above - however I have not tested this configuration so your results may vary! 
    {: .prompt-info }

#### KVM _guest_

1. The paravirtualised `Virtio RNG` kernel module, `virtio-rng.ko`, depends upon the Linux's core HWRNG driver `rng-core.ko` in order to "feed" the kernel's entropy pool from an external source. Verify the KVM _guest_ has the `rng-core.ko` kernel module as <u>either</u> an externally loadable module or compiled directly into the running Linux kernel itself. If the `virtio-rng.ko` kernel module is an externally loadable module ensure it has been loaded:
```bash
   # Kernel module
stat /lib/modules/$(uname -r)/kernel/drivers/char/hw_random/rng-core.ko
sudo modprobe --verbose rng-core.ko

   # Compiled in-kernel
grep rng-core.ko /lib/modules/$(uname -r)/modules.builtin
```
    {: .nolineno }

2. Verify the KVM _guest_ has the `virtio-rng.ko` kernel module as <u>either</u> an externally loadable module or compiled directly into the running Linux kernel itself. If the `virtio-rng.ko` kernel module is an externally loadable module ensure it has been loaded:
```bash
   # Kernel module
stat /lib/modules/$(uname -r)/kernel/drivers/char/hw_random/virtio-rng.ko
sudo modprobe --verbose virtio-rng.ko

   # Compiled in-kernel
grep virtio-rng.ko /lib/modules/$(uname -r)/modules.builtin
```
    {: .nolineno }
> `modprobe` will automatically pull in `rng-core.ko` if it is not already loaded
    {: .prompt-info }

3. Check that the HWRNG core detected the VirtIO RNG interface, `virtio`, as both an available and selected ("current") source of entropy for the KVM _guest_'s kernel:
```bash
cat /sys/devices/virtual/misc/hw_random/rng_available
cat /sys/devices/virtual/misc/hw_random/rng_current
```
    {: .nolineno }
> Linux kernel developments in the later 3.X series interact with the VirtIO RNG interface in a manner whereby the entropy passed via the paravirtualised interface is "fed" directly to the KVM _guest_ kernel's entropy pool (<a html="http://rhelblog.redhat.com/2015/03/09/red-hat-enterprise-linux-virtual-machines-access-to-random-numbers-made-easy/">source</a>). For completeness I have included the remaining steps (for this subsection) that involve configuring and validating the otherwise unnecessary `rng-tools` daemon. 
    {: .prompt-info }

4. Check that the corresponding `/dev/hwrng` character device node has been exposed within the KVM _guest_. This device node serves as the bridge between the paravirtualised RNG interface provided to the guest and the `rng-tools` daemon, `rngd`, which "feeds" entropy to the KVM _guest_'s kernel:
```bash
stat /dev/hwrng
```
    {: .nolineno }
 
5. Install the `rng-tools` Debian binary archive wiithin the KVM _guest_. By default the `rngd` daemon will utilise the `/dev/hwrng` character device node as the input source for random data so no additional configuration is necessary for getting the `rngd` daemon running after installation:
```bash
sudo apt-get install --yes rng-tools
```
    {: .nolineno }

6. Check that the `rngd` daemon has successfully opened the `/dev/hwrng` character device node with read permissions:
```bash
$ lsof /dev/hwrng
COMMAND PID USER   FD   TYPE DEVICE SIZE/OFF  NODE NAME
rngd    414 root    3r   CHR 10,183      0t0 10061 /dev/hwrng
```
    {: .nolineno }

7. Check that the KVM _guest_'s kernel entropy pool is being "fed" from the `rngd` daemon:
```bash
cat /proc/sys/kernel/random/entropy_avail
```
    {: .nolineno }
The above command should return a single value in the excess of 1000; such a value indicates that entropy pool is being filled correctly by the `rngd` daemon via the paravirtualised VirtIO RNG interface.

8. Verify the _quality_ of the randomness produced via the paravirtualised VirtIO RNG interface (ultimately obtained from the OneRNG HWRNG USB) still passes the FIPS 140-2 cryptographic standard:
```bash
sudo cat /dev/hwrng | rngtest --blockcount=100 < /dev/hwrng |& grep 'failures\|successes'
```
    {: .nolineno }

### USB Passthrough

As <a href="#virtio-rng">previously identified</a>, the paravirtualised VirtIO RNG interface requires KVM _guest_ support in order for entropy generated on the KVM _host_ to be passed to it. Chances are VirtIO's broad support (i.e. _guest_ implementation) for numerous, popular operating systems such as GNU/Linux, OpenBSD, FreeBSD, NetBSD, Plan 9, and Windows will cover the vast majority of desired use cases.
For edge cases whereby VirtIO support is not available (or not feasible/suitable) we can leverage QEMU/KVM's generic USB passthrough capability as a means of providing an entropy generator source to a **single** KVM _guest_.

Sadly QEMU/KVM does <u>not</u> support the ability to passthrough a single USB device to multiple KVM _guests_, attempting to do so results in the following error: 
```bash
error: Requested operation is not valid: USB device 003:002 is in use by driver QEMU, domain moonbase_rng
```
{: .nolineno }

While this behaviour makes sense for devices such as USB Mass Storage devices it would have been interesting to have had a pre-initialised OneRNG HWRNG USB (i.e. enable internal entropy generation via raw `cmd` messages) passed through in read-only mode to multiple KVM _guests_. At that stage you could configure the `rngd` daemon on each of the KVM _guests_ to source its entropy from the `/dev/ttyACM$` character device node. 

#### KVM _host_

1. Check that the OneRNG service is not running and the `rngd` daemon is no longer feeding the entropy pool from the OneRNG HWRNG USB `/dev/ttyACM$` character device node:
```bash
sudo systemctl stop rng-tools
sudo lsof /dev/ttyACM$
```
    {: .nolineno }
The above command should return an empty response indicating that the `/dev/ttyACM$` character device node is not being held by any running process(es) on the KVM _host_.

2. Specify the "vendor" and "product" ID pair to either the Libvirt CLI utility (`virt-install`) or, alternatively, via the QEMU (`qemu-system-x86_64`) invocation during VM creation/definition for passing the OneRNG HWRNG USB into the KVM *guest*:
```bash
   # Libvirt 'virt-install' 
--host-device 1d50:6086 \

   # QEMU 'qemu-system-x86_64' 
-usb \
-device usb-host,vendorid=0x1d50,productid=0x6086 \
```
    {: .nolineno }

3. Check that the `qemu-system-x86_64` process has successfully opened the USB `/dev/ttyACM$` character device node with read <u>and</u> write permissions. Both interaction permission types are required as the KVM _guest_ will need to interact with the OneRNG HWRNG USB in the same manner the KVM host typically would (i.e. sending raw commands for initialising/modesetting the OneRNG HWRNG USB):  
```bash
$ lsof /dev/ttyACM0
COMMAND    PID         USER   FD   TYPE DEVICE SIZE/OFF  NODE    NAME
qemu-syst 30203 libvirt-qemu  24u  CHR  189,387  0t0     945139  /dev/ttyACM0
```
    {: .nolineno }

#### KVM _guest_

1. Check that the OneRNG HWRNG USB device has been successfully passed through from the KVM _host_ to the KVM _guest_:
```bash
$ lsusb -d 1d50:6086
Bus 003 Device 002: ID 1d50:6086 OpenMoko, Inc. OneRNG entropy device
```
    {: .nolineno }
The above command should return a single line displaying the unique "Bus", "Device", and "ID" combination allocated to the OneRNG HWRNG USB.

2. Given that the hardware environment is essentially a "simplified" baremetal scenario (i.e. reduced amount of peripherals, PCI devices, buses, etc.) proceed to follow the installation and configuration steps outlined in the <a href="#baremetal">baremetal</a> section.


## LXC

Several testing environments I interact with leverage the OS-level virtualisation userspace utilities, <a href="https://en.wikipedia.org/wiki/LXC">Linux Containers</a> (LXC), for rapidly provisioning "namespaced", resource constrained ("cgroups"), lightweight GNU/Linux systems (i.e. "`chroot` on steriods"). One particular characteristic of OS-level virtualisation is that LXC _guests_ share the <u>same</u> Linux kernel as the underlying _host_ and also the <u>same</u> entropy pool. 

With this in mind it is possible to provision "standard" (i.e. Debian GNU/Linux Jessie LXC container template) LXC _guests_ that will automatically consume entropy from the underlying LXC _host_ via their own respective `/dev/random` character device node (i.e. not "bind" mounted from the LXC _host_). Assuming the LXC _host_ has a correctly configured OneRNG HWRNG USB the generated entropy can be passed through <u>without</u> any intermediate transport protocol (e.g. VirtIO) to an arbitrary amount of LXC _guests_. It is as simple as provisioning a LXC _guest_ and running the entropy hungry application (e.g. `gpg`) to transparently consume the entropy generated by the OneRNG HWRNG USB.

This section covers the steps necessary for passing the OneRNG HWRNG USB character device node through into a _privileged_ LXC container and running the OneRNG service from within a LXC _guest_. From examining the LXC <a html="https://linuxcontainers.org/lxc/manpages/man5/lxc.container.conf.5.html">man page</a> I discovered that there are two plausible methods for "passing through" the OneRNG HWRNG USB character device node to a LXC _guest_:

1. Specifying the OneRNG HWRNG USB character device node's `major` and `minor` values (e.g. `166:0`) explicitly via the <a html="https://www.kernel.org/doc/Documentation/cgroup-v1/devices.txt">"devices" subsystem cgroup</a>. By leveraging the <a href="https://www.kernel.org/doc/Documentation/cgroup-v1/devices.txt">devices cgroup</a>, LXC offers granular permission based control (read, write, and `mknod`) when exposing LXC _host_ devices to LXC _guests_. This approach employs the following configuration structure:
```bash
lxc.cgroup.devices.allow $DEV_TYPE $MAJOR:$MINOR $PERMS`. 
```
    {: .nolineno }

2. Specifying the OneRNG HWRNG USB character device node's unique `ttyACM$` node via the <a html="http://man7.org/linux/man-pages/man7/mount_namespaces.7.html">mount namespace</a>. While typically utilised for sharing specified directories (be it locally or on remote storage) to LXC _guests_ the mount namespace can be used to "bind" mount device node(s) from the LXC _host_ to the LXC _guest_. This approach employs the following configuration structure:
```bash
lxc.mount.entry = $HOST_MOUNT $GUEST_MOUNT $MOUNT_OPTS,create=$CREATE_TYPE
```
    {: .nolineno }

Unlike QEMU/KVM, LXC does not appear to support using either the OneRNG HWRNG USB's unique USB "vendor:model" identifier (useful when using a <u>single</u> OneRNG HWRNG USBs) or the USB "bus:device" identifier (useful when using _multiple_ OneRNG HWRNG USBs) within the LXC _guest_'s configuration file.
Unfortunately the two identification methods used by LXC may result in the LXC _guest_ failing to start as the underlying host's kernel has enumerated the OneRNG HWRNG USB with a different device node "major:minor" pairing or device node name.
The QEMU/KVM identification methods may eventually be added as usable options within the LXC container configuration file given that modern versions of LXC have demonstrated the ability to hotplug USB devices (albeit to running LXC _guests_ only) by specifying the USB device's "vendor:model" identification pair (<a html="https://insights.ubuntu.com/2017/03/29/usb-hotplug-with-lxd-containers/">source</a>).

The following operations cover the "devices" cgroup approach given the fact it is was originally designed to: 
> "_[...] track and enforce open and mknod restrictions on device files._" (<a html='https://www.kernel.org/doc/Documentation/cgroup-v1/devices.txt'>source</a>). 

> I have not attempted the alternative approach ("mount" namepsace) and therefore cannot comment on its viability for this particular scenario.
{: .prompt-info }

1. Create a Debian GNU/Linux 8.0 "Jessie" LXC _guest_ that will be targeted for passing the OneRNG HWRNG USB through to: 
```bash
sudo lxc-create --name moonbase_lxc \
                   --template debian -- \
                   --release=jessie \
                   --arch=amd64
```
    {: .nolineno }

2. Create a dedicated "hook" Bash script, e.g. `/var/lib/lxc/moonbase_lxc/autodev.sh`, that will be invoked at boot whenever the previously defined LXC _guest_ is started. This small script automates the commands required for enumerating the OneRNG HWRNG USB character device node within the LXC *guest*'s `/dev` directory:
```bash
   #!/usr/bin/env bash
    
   # Creates the ttyACM$ device node for access by the 'rng-tools' daemon
   # This mimics the default 'udev' behaviour in a Debian "Jessie" on a baremetal system
   # Credits: http://fault.itsprite.com/running-systemd-based-container-in-lxc/
mknod ${LXC_ROOTFS_MOUNT}/dev/ttyACM$ c 166 0
chown root:dialout ${LXC_ROOTFS_MOUNT}/dev/ttyACM$
chmod 660 ${LXC_ROOTFS_MOUNT}/dev/ttyACM$
```
    {: .nolineno }
    * Substitute `$` with the number allocated by the underlying LXC _host_. 

3. Permit the execution of the `autodev.sh` Bash script:
```bash
sudo chmod 755 /var/lib/lxc/moonbase_lxc/autodev.sh
```
    {: .nolineno }

4. Edit the "moonbase_lxc" LXC container configuration file so as to: 1) permit read and write access to the OneRNG HWRNG USB character device node and, 2) specify the `autodev.sh` hook script for invocation at container startup:
```bash
   # R/W access to OneRNG HWRNG USB
lxc.cgroup.devices.allow = c 166:0 rw

   # OneRNG HWRNG USB character device node auto-creation
lxc.autodev = 1
lxc.hook.autodev = /var/lib/lxc/moonbase_lxc/autodev.sh
```
    {: .nolineno }

As per the <a html="https://linuxcontainers.org/lxc/manpages/man5/lxc.container.conf.5.html">LXC man page</a> the `lxc.hook.autodev` is used to 
> "_[...] to assist in populating the `/dev` directory of the container when using the `autodev` option for systemd based containers_". 
Given that the Debian GNU/Linux 8.0 "Jessie" LXC _guest_ utilises systemd this hook mount ordering option is most suitable for this scenario.

4. Start the preconfigured LXC _guest_:
```bash
sudo lxc-start --name moonbase_lxc \
                  --daemon
```
    {: .nolineno }

5. Access the LXC _guest_'s console:
```bash
sudo lxc-console --name moonbase_lxc
```
    {: .nolineno }
    * The remaining operations are performed as the `root` user within the LXC _guest_.

3. Install the necessary prerequisite packages:
```bash
apt-get install --yes rng-tools at python-gnupg openssl
```
    {: .nolineno }

4. Download the OneRNG Debian binary archive and save it to the `root` user's dedicated directory:
```bash
wget http://moonbaseotago.com/onerng/onerng_3.5-1_all.deb --output-directory=/root
```
    {: .nolineno }

5. Install the OneRNG Debian binary archive. The Debian binary package installer, `dpkg`, <u>will</u> error out midway through the installation (and subsequent configuration) of the OneRNG package due to its `postinst` script invoking `udev` which in turn fails (return code 2):
```bash
$ dpkg --install onerng_3.5-1_all.deb
Selecting previously unselected package onerng.
(Reading database ... 17300 files and directories currently installed.)
Preparing to unpack onerng_3.5-1_all.deb ...
Unpacking onerng (3.5-1) ...
Setting up onerng (3.5-1) ...
dpkg: error processing package onerng (--install):
 subprocess installed post-installation script returned error exit status 2
Errors were encountered while processing:
 onerng
```
    {: .nolineno }
Despite `dpkg` marking the `onerng` package as being in an installed but "half configured" state (as per `dpkg --list | grep onenrg`), the OneRNG service still has all of its configuration and service/daemon files copied to the appropriate locations. 

6. Create a systemd service file, `/lib/systemd/system/onerng.service`, for starting the OneRNG service at boot within the LXC _guest_:
```bash
[Unit]
Description=Onerng Moonbase Otago USB HWRNG USB Daemon
Documentation=http://onerng.info/
ConditionPathExists=/dev/ttyACM$
ConditionVirtualization=container
‎
[Service]
Type=forking
ExecStart=/sbin/onerng.sh daemon ttyACM$
‎
[Install]
WantedBy=multi-user.target
```
    {: .nolineno }
Given that we explicitly know the OneRNG HWRNG USB character device node (e.g. `/dev/ttyACM0`) being passed through to the LXC _guest_ we can invoke the main OneRNG service script, `/sbin/onerng.sh`, against the OneRNG HWRNG USB character device node. The above systemd service file will start the OneRNG service once the LXC _guest_ has fully initialised. 

10. Enable the `onerng.service` systemd service in order to start the OneRNG service at boot:
```bash
systemctl enable onerng.service
```
    {: .nolineno }

11. Start the `onerng.service` systemd service:
```bash
systemctl start onerng.service
```
    {: .nolineno }

12. Confirm the `onerng.service` systemd service is running:
```bash
systemctl status onerng.service
```
    {: .nolineno }

13. Confirm the `rngd` daemon is feeding the Linux kernel's entropy pool from data provided by the OneRNG HWRNG USB:
```bash
cat /proc/sys/kernel/random/entropy_avail
```
    {: .nolineno }
The above command should return a single value in the excess of 1000. Such a value indicates Linux's entropy pool is being filled correctly by the `rngd` daemon and OneRNG HWRNG USB.

14. Verify the _quality_ of the randomness produced via the OneRNG HWRNG USB passes the FIPS 140-2 cryptographic standard:
```bash
sudo cat /dev/ttyACM$ | rngtest --blockcount=100 |& grep 'failures\|successes'
```
    {: .nolineno }

## Distributing Entropy

Practically all my virtualised (KVM or LXC) environments reside on my server ("Octeron") and so the aforementioned approaches to providing entropy to the targeted _guest_(s) is sufficiently flexible for the vast majority of my scenarios. Nevertheless, future scenarios/projects may result in a mixture of virtual and baremetal machines and therefore the listed approaches will not suffice for discrete, external baremetal hosts in such an environment. 

With this in mind I set about piecing together a primitive, but functional, entropy _broker_ and entropy _consumer_ setup (i.e. <a href="https://en.wikipedia.org/wiki/Client%E2%80%93server_model">client-server model</a>) that would facilitate the distribution of entropy (generated by the OneRNG HWRNG USB) over a TCP/IP network. Credit should be given to the <a html="https://lwn.net/Articles/546428/">LWN article</a> which covered a high level overview of a fully-fledged entropy _broker_ and entropy _consumer_ <a html="https://www.vanheusden.com/entropybroker/#download">utility</a> as it served as inspiration for "building" my own entropy _broker_ & _consumer_ setup by using existing system utilities. 

### Limitations

Given its comparative simplicity in relation to the entropy broker discussed in the LWN article there are notable disadvantages to this simplistic setup that may make it unsuitable for deployment in your own environment. These noteworthy disadvantages are:

* Inability to of _rate limit_ entropy on a per_-consumer_ basis
* The same entropy byte stream is sent to all _consumers_, this may make it easier for malicious users to determine the state of the _consumer_'s entropy state
* Lack of authentication between the _broker_ and _consumer_(s)
* Lack of encryption between the _broker_ and _consumer_(s)

I attempted to use passwordless SSH public key authentication to resolve, or at least mitigate to some degree, the authentication and encryption disadvantages of my approach **without** success. From a brief debugging phase it appears that the byte stream wouldn't buffer as required when piped via a SSH forwarding tunnel.

### Entropy _broker_

1. Check that the OneRNG service is installed correctly and is currently "feeding" the entropy pool of the host via the `/dev/ttyACM$` character device node. Refer to the <a href="#baremetal">baremetal</a> section for the setting up the OneRNG HWRNG USB on a Debian GNU/Linux 8.0 "Jessie" system.

2. Install the "SOcket CAT" (`socat`) utility that will provide the necessary byte stream redirection for buffering entropy from the OneRNG HWRNG USB character device node to a TCP socket:
```bash
sudo apt-get install --yes socat
```
    {: .nolineno }

3. Create a systemd service _template_ file, `/etc/systemd/system/onerng-broker-server.service`, that invokes the `socat` listener with the STDIN stream sourcing from the OneRNG HWRNG USB character device node: `/dev/ttyACM$`:
```bash
[Unit]
Description=OneRNG Broker Server
ConditionPathExists=/dev/ttyACM$
‎
[Service]
Type=simple
ExecStart=/usr/bin/socat FILE:/dev/ttyACM$ TCP-LISTEN:55000,fork
RemainAfterExit=True
Restart=on-failure
RestartSec=5
‎
[Install]
WantedBy=multi-user.target
```
    {: .nolineno }
I was hoping to employ systemd's "template" capabilities for enabling flexible creation of service files to provide a quick way of provisioning multiple OneRNG HWRNG USB devices by the entropy *broker*. Unfortunately this was not possible as the `TCP-LISTEN` argument requires a unique port for each `ttyACM$` character device node it reads from. 

4. Enable the `onerng-broker-server.service` systemd service file to ensure it starts during system initialisation:
```bash
sudo systemctl enable onerng-broker-server.service`
```
    {: .nolineno }

5. Start the `onerng-broker-server.service` systemd service:
```bash
sudo systemctl start onerng-broker-server.service
```
    {: .nolineno }

6. Confirm that the `socat` utility is reading from the specified OneRNG HWRNG USB character device node and buffering the byte stream to the desired TCP socket:
```bash
socat TCP:127.0.0.1:55000 - | base64
```
    {: .nolineno }
The above command should result in a stream of alphanumeric characters populating the console. Once confirmed proceed to terminate the blocking command with the SIGINT signal (ctrl+c). 

### Entropy _consumer_

1. Install the `socat` and the `rng-tools` packages:
```bash
sudo apt-get install --yes socat rng-tools
```
    {: .nolineno }

2. Disable the default `rng-tools` SysVinit init script from starting the `rngd` daemon at boot:
```bash
sudo systemctl disable rng-tools
```
    {: .nolineno }

3. Create a static, <a href="https://en.wikipedia.org/wiki/Named_pipe">named pipe</a> that will be used by `socat` for redirecting the byte stream from the entropy _broker_'s TCP socket to:
```bash
sudo mkfifo /dev/onerng-pipe
```
    {: .nolineno }

4. Create a systemd service file, `/etc/systemd/system/onerng-broker-client.service`, that will have `socat` redirect the byte stream received from connecting to the TCP socket on the _broker_ to the buffered named pipe:
```bash
[Unit]
Description=OneRNG Broker Client
After=network-online.service
Before=onerng-rngd.service
‎
[Service]
Type=simple
ExecStart=/usr/bin/socat TCP:$IP_OF_BROKER:55000 PIPE:/dev/onerng-pipe
Restart=on-failure
RestartSec=5
‎
[Install]
WantedBy=multi-user.target
```
    {: .nolineno }

5. Enable the `onerng-broker-client.service` systemd service file to ensure it starts during system initialisation:
```bash
sudo systemctl enable onerng-broker-client.service
```
    {: .nolineno }

6. Start the `onerng-broker-client.service` systemd service:
```bash
sudo systemctl start onerng-broker-client.service
```

7. Confirm that the `socat` process is reading input from the _broker_'s TCP socket and is buffering the byte stream to the named pipe (`/dev/onenrg-pipe`):
```bash
base64 < /dev/onerng-pipe
```
    {: .nolineno }
The above command should result in a stream of alphanumeric characters populating the console; output here illustrates that the complete _broker_<->_consumer_ "chain" has been correctly established. Once confirmed proceed to terminate the blocking command with the SIGINT signal (ctrl+c).

8. Edit the `rngd` daemon configuration file (`/etc/default/rng-tools`) and set the `HRNGDEVICE` variable to that of the named pipe (`/dev/onenrg-pipe`).
As the TCP connection between the consumer and the broker is not encrypted I recommend passing additional options that ensure the byte stream ingested by the `rngd` daemon from the entropy broker only _contributes_ to the entropy pool.
This particular rate-limiting, consumption restricted safeguard protects against potential "man-in-the-middle" attacks as the intruder cannot dictate the _entire_ state of the entropy pool of the _consumer_(s).  
```bash
HRNGDEVICE=/dev/onerng-pipe
RNGDOPTIONS="--fill-watermark=33% --feed-interval=90"
```
    {: .nolineno }

9. Create a systemd service file, `/etc/systemd/system/onerng-rngd.service`, that will invoke the `rngd` daemon in a similar fashion to its corresponding, default SysVinit counterpart:
```bash
[Unit]
Description=OneRNG rngd-daemon
After=onerng-broker-client.service
‎
[Service]
Type=forking
EnvironmentFile=/etc/default/rng-tools
ExecStart=/usr/sbin/rngd -r $HRNGDEVICE $RNGDOPTIONS
‎
[Install]
WantedBy=multi-user.target
```
    {: .nolineno }
The reason we do not employ the preinstalled SysVinit `rngd` service file (`/etc/init.d/rng-tools`) is because the default init script checks the `HRNGDEVICE` variable's value and if its path value does not correspond to a character device node (e.g. `/dev/hwrng`, `/dev/ttyACM0`) it fails and terminates. As this setup uses a named pipe as an input source the startup script will fail and the `rngd` daemon wont run!

10. Enable the `onerng-rngd.service` systemd service file to ensure it starts during system initialisation:
```bash
sudo systemctl enable onerng-rngd.service
```
    {: .nolineno }

11. Start the `onerng-rngd.service` systemd service:
```bash
sudo systemctl start onerng-rngd.service
```
    {: .nolineno }

12. Confirm the `rngd` daemon is running with the configuration options specified in the `/etc/default/rng-tools` file:
```bash
ps aux | grep rngd
```
    {: .nolineno }

13. Confirm the `rngd` daemon is feeding the entropy _consumer_ kernel's entropy pool from the byte stream sourced from the named pipe (`/dev/onenrng-pipe`):
```bash
cat /proc/sys/kernel/random/entropy_avail
```
    {: .nolineno }
The above command should return a single value in the excess of 1000; such a value indicates that entropy pool is being filled correctly by the `rngd` daemon.

14. Verify the quality of the randomness produced via the byte stream sourced from the named pipe (`/dev/onenrng-pipe`) passes the FIPS 140-2 cryptographic standard:
```bash
sudo cat /dev/onerng-pipe | rngtest --blockcount=100 |& grep 'failures\|successes'
```
    {: .nolineno }

## Upstream contribution

As implicitly illustrated in the LXC subsection, the OneRNG Debian binary archive was not constructed with OS level virtualisation in mind. In an effort to improve the package's portability within OS level virtualisation environments I took it upon myself to disassemble the package and add/edit the following components:

* Created a systemd service file template, `/lib/systemd/system/onerng@.service` (outlined in the LXC section), that is dynamically generated on a per OneRNG HWRNG USB character device node basis by the `DEBIAN/postinst` script.

* Heavily modified the `DEBIAN/postinst` "control" file in order to provide OS virtualisation environment detection. If the Bash script detects a Docker or LXC environment it will:
    1. Iterate through all available TTY ACM character device nodes
    2. Check to see if their respective vendor USB major:minor number matches up to the OneRNG HWRNG USB's
    3. Upon finding a match generate a systemd service file (using the system service file template) based off the OneRNG HWRNG USB character device node identifier/name

* Created the `DEBIAN/postrm` "control" file that stops the dedicated systemd service file should the installation have been performed on within a OS level virtualisation environment. 

The final, reassembled OneRNG package containing these additions/editions can be downloaded from my Google Drive share here: <a html="https://drive.google.com/file/d/0B459txgVvoaUOE9MSHB4X0Nldnc/view?usp=sharing">Link</a> (md5sum: `b912d6405da0c962b498863a46d86619`). 
From my own testing I can confirm the package installs/uninstalls correctly and that the `onerng.sh` script is invoked by the OneRNG specific systemd service file in the same manner that `udev` does within a baremetal environment (i.e. at boot and immediately after installation).

I've sent the package upstream to a OneRNG core member - <a html="http://onerng.info/history.html">Jim Cheetham</a> - for his consideration should he wish to include these changes in the upstream OneRNG package.

## Final Words

Understanding more about the concepts of randomness/entropy and its scarcity within both traditional hardware-accelerated virtualised environments and isolated (i.e. little to no user based inputs) hardware environments (without entropy generating CPU extensions) has deepened my appreciation of affordable HWRNG devices. Interacting with Moonbase Otago's OneRNG HWRNG USB has been a pleasurable experience given the extensive Linux support from kernel space (`cdc_acm`) and user space (`rng-tools`) perspectives.

Being a proponent of <a html="https://opensource.org/">open source</a> it is encouraging to see small hardware vendors such as Moonbase Otago adopt such principles in both their hardware and software implementations. In the very spirit of the GPL I have been able to leverage the foundation established by the OneRNG team, construct/implement a particular feature that I now utilise, and ultimately contribute said feature back to the wider community.

In closing I'd like to mention an excellent blog post, "<a html="https://www.2uo.de/myths-about-urandom/">Myths about /dev/urandom</a>", written by Thomas Hühn which corrects numerous misconceptions (which I myself had falled foul to) regarding `/dev/urandom`'s viability for producing cryptographically "strong" randomness for consumption by various utilities/applications (e.g. SSH keys). Not only did Thomas's blog post correct my perception of `/dev/urandom` it also refreshed (and furthered) my understanding of the difference between `/dev/random` and `/dev/urandom` from Linux's perspective.

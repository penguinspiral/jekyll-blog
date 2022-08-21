---
title: Configuring Unprivileged LXC containers in Debian 8
date: '2015-09-09 05:34:00'
categories: [Virtualisation]
tags: [lxc, cgroups, namespaces]
---

The gradual maturity of Linux Control Groups and in-kernel namespaces (i.e. net, user, mount, IPC, etc) has enabled powerful OS-level virtualisation utilities such as <a href="https://en.wikipedia.org/wiki/Docker_(software)">Docker</a> and <a href="https://en.wikipedia.org/wiki/LXC">LXC</a> (Linux Containers) to offer a lightweight, high-performing alternative to typical hardware based virtualisation (e.g. KVM). 

With OS-level virtualisation the host's kernel handles all system calls generated from OS-level VMs resulting in less resource overhead when compared to the hardware virtualisation approach which requires an intermediary hypervisor (e.g. KVM, Hyper-V) to emulate the system calls on behalf of the VM.

The isolation of OS-level VMs is performed entirely in the kernel (in software) through the use of <a href="https://en.wikipedia.org/wiki/Linux_namespaces">namespaces</a>; this eliminates the need for any particular hardware (e.g. svn, vmx) that is presently necessary for _accelerated_ <a href="https://en.wikipedia.org/wiki/Hardware-assisted_virtualization">hardware based virtualisation</a>.  
While the nature of these characteristics enables greater utilisation of hardware resources when deploying Linux-only applications (even across differing hardware platforms) there are notable drawbacks pertaining to VM migration inflexibility (unless hosts have same kernel), Linux-only support, and comparably weaker security. The latter of which has been substantially improved upon with the advent of _unprivileged containers_ in LXC 1.0.

## Intro

During my time at the North America LinuxCon event in Seattle I attended a wide range of technical talks ranging from Linux kernel performance tuning to the potential applications of the BPF (Berkley Packet Filter) in-kernel virtual machine. One particular topic of interest that cropped up numerous times across the majority of keynotes and technical talks was **Containers** (<a href="https://en.wikipedia.org/wiki/OS-level_virtualization">OS-level virtualisation</a>) and the variety of tools that make the most effective use of them in an enterprise environment (e.e. Docker, Kubernetes). Seeing as they were mentioned on so many occasions I felt it benefical to focus my time and effort on learning the underlying tools/technologies to a greater extent before getting my hands dirty with applications like Docker.

Having configured LXC within Debian 7 "Wheezy" on my server a few years back I was already aware of the basic concepts relating to Linux kernel `namespaces` and `control groups` from a LXC perspective. One important aspect I learnt about LXC early on was that if a container ran as the `root` user (as was the norm initially) was compromised (e.g. a buggy syscall) than the underlying host was _entirely_ at the mercy of the malicious, `root` privilege wielding attacker - yikes! 
Various security "wrappers" were, and still are, available to help reduce the attack surface (e.g. <a href="https://en.wikipedia.org/wiki/AppArmor">AppArmor</a>, <a href="https://en.wikipedia.org/wiki/Security-Enhanced_Linux">SELinux</a>, <a href="https://en.wikipedia.org/wiki/Seccomp">seccomp</a>, <a href="https://grsecurity.net/">grsecurity</a>). In spite of these various protection mechanisms Stéphane Graber, an upstream maintainer of LXC and Canonical employee, states that the implementation of `user namespaces` required for enabling unprivileged containers in  LXC is:
> "[...] probably the only way of making a container actually safe"

Stéphane continues to explain that LXC's attack vector is considerably reduced when operating as an `unprivileged container`: 
> "LXC is no longer running as _root_ so even if an attacker manages to escape the container, he’d find himself having the privileges of a regular user on the host." (<a href="https://www.stgraber.org/2014/01/01/lxc-1-0-security-features/">source</a>).
  
In an effort to learn more about the LXC userspace (`/usr/bin/lxc-*`) tools I migrated some of my existing hardware based VMs to _privileged_ LXC containers (VMs), consequently benefiting from a notable improvement in performance whilst reducing the VM's overall memory footprint. My own curiosity resulted in me exploring (a.k.a. "googling") the possibility of running GUI applications such as <a href="https://www.geticeweasel.org/">Iceweasel</a> or <a href="https://en.wikipedia.org/wiki/Skype">Skype</a> within a LXC container. 
Ultimately, this guide stems from the obvious requirement in Stéphane Graber's <a href="https://www.stgraber.org/2014/01/17/lxc-1-0-unprivileged-containers/">guide</a> to running GUI applications within `unprivileged containers`. 
While modern versions of Ubuntu (14.04 upwards) are shipping a working unprivileged LXC setup out of the box the Debian Jessie 8.2 offering is sadly lacking in comparison. Having found no thorough setup guides for Debian I thought I would share my step-by-step solution to hopefully save someone from facing the same struggles I did when configuring `unprivileged containers` on a Debian Jessie 8.2 host.

### Packages Used 

* `lxc`: 1:1.0.6-6+deb8u1
* `cgroup-tools`:0.41-6
* `uidmap`: 1:4.2-3
* `linux-image-3.16.0-4-amd64`: 3.16.7-ckt11-1+deb8u3
* `systemd`: 215-17+deb8u2

> This guide _assumes_ you are using the Debian supplied kernel provided by the linux-image-3.16.0-4-amd64 package. If you are using a custom kernel please check you have Control Group and namespace support (`lxc-checkconfig`) before proceeding.
{: .prompt-info }

### Establishing LXC unprivileged container path equivalents

The tools required for creating and configuring LXC `unprivileged containers` do _not_ automatically create the user specific directory/file layout required by "user owned" LXC containers. The following system-wide to per-user basis LXC configuration layout mappings have been sourced from Stéphane Graber's blog (<a href="https://www.stgraber.org/2014/01/17/lxc-1-0-unprivileged-containers/">here</a>):

```bash
/etc/lxc/lxc.conf     => ~/.config/lxc/lxc.conf
/etc/lxc/default.conf => ~/.config/lxc/default.conf
/var/lib/lxc          => ~/.local/share/lxc
/var/lib/lxcsnaps     => ~/.local/share/lxcsnaps
/var/cache/lxc        => ~/.cache/lxc
```

Recreate this layout in the order above as follows:

```bash
mkdir --parents ~/.config/lxc
touch ~/.config/lxc/{lxc,default}.conf
mkdir --parents ~/.local/share/{lxc,lxcsnaps}
mkdir --parents ~/.cache/lxc
```

## Enabling kernel features and extending user UIDS & GIDS

The Debian maintained 3.16.0-4 Linux kernel used by Jessie 8.2 has a crucial kernel feature required for cloning `user namespaces` disabled by default. 
According to the Debian bug report <a href="https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=712870">#712870</a> `user namespaces` have been enabled in the Debian tailored Linux kernels (`3.12-1~exp1` upwards) since late November 2013 but have:
> "Restrict creation of user namespaces to root (`CAP_SYS_ADMIN`) by default (`sysctl:kernel.unprivileged_userns_clone`)". 

### Enabling unprivileged user namespace creation

To allow an unprivileged user to create a user namespace we need to enable that feature in the kernel:

1. Create a `sysctl` configuration file `/etc/sysctl.d/80-lxc-userns.conf` for enabling the required `unprivileged_userns_clone` flag at boot:
```bash
kernel.unprivileged_userns_clone=1
```

2. Reload `sysctl` so it takes into account the newly created `/etc/sysctl.d/80-lxc-userns.conf` configuration file:
```bash
sudo sysctl --system
```

3. Check that the `unprivileged_userns_clone` flag has been set for the running session: 
```bash
cat /proc/sys/kernel/unprivileged_userns_clone
```
If `sysctl` has done its job correctly the value returned from the above command should be: `1`.

### Creating subordinate ids

4. Install the `uidmap` package required for allowing unprivileged users create UID and GID mappings within `user namespaces`:
```bash
sudo apt-get install --yes uidmap
```

5. Create a "subid" (subordinate id) range for both user UIDS and GIDS which will serve as a mapping inside `unprivileged containers`:
```bash
sudo usermod --add-sub-uids 100000-165536 $USER
sudo usermod --add-sub-gids 100000-165536 $USER 
``
These subids will persist between system reboots as `usermod` will have written them to `/etc/subuid` and `/etc/subgid` respectively.

6. Configure the user specific LXC default configuration file, `~/.config/lxc/default.conf`, for consuming the 100000-165536 UID _and_ GID ranges for all `unprivileged containers`. This ensures processes inside the `unprivileged container` have their respective UIDS and GIDS remapped from the standard 0-65536 range to the 100000-165536 range on the host. The host is aware that these "subid" mappings (stored in `/etc/subuid` & `/etc/subgid`) are owned by the user (`$USER`) and consequently enforce preexisting user restrictions upon them:
```bash
lxc.id_map = u 0 100000 65536
lxc.id_map = g 0 100000 65536
```

## Configuring cgroup tools

My own investigations into configuring `unprivileged containers` in Debian Jessie lead to the unearthering of _two_ daemons that provided high-level control for dynamically manipulating control groups on the fly: 

1. `cgmanager`: Part of the `cgmanager` package that enables applications and users to configure cgroups via D-Bus requests.

2. `cgrulesengd`: Part of the `cgroup-tools` package that detects when processes change its "effective" UID or GID and inspects a list of rules to determine what to do with the process; e.g. move process to a preconfigured control group.

Both offerings provided an operable environment for deploying working `unprivileged containers` but I found the latter to be more suited for my needs.

The package `cgroup-tools` contains several userspace command-line utilities and a system daemon, `cgrulesengd`, that interfaces with the `libcgroup` library for manipulating, controlling, administrating, and monitoring `cgroup` "controllers" (e.g. `blkio`, `cpu`, etc).

### Configure cgrulesengd

Examining the `cgroup-tools` package's `/usr/share/doc/cgroup-tools/TODO.Debian` reveals:
> "[...] come up with an failsafe, upgrade-proof and admin friendly initscript" 

We need to configure the `cgrulesengd` daemon's startup/shutdown behaviour ourselves, view it as an opportunity to learn more about the 'cgroup-tools' utilities and how they work together. The `/usr/share/doc/cgroup-tools/examples/` directory contains various template configuration files that are utilised later on in this guide. 

Install the `cgroup-tools` package:
```bash
sudo apt-get install --yes cgroup-tools
```

#### libcgroup configuration ~ cgred.conf

Create the `/etc/sysconfig` directory for storing the provided example "Control Group Rules Engine Daemon" (`cgrulesengd`) configuration file, `/usr/share/doc/cgroup-tools/examples/cgred.conf`, which will be later used by the `cgrulesengd` daemon:
```bash
sudo mkdir /etc/sysconfig
sudo cp /usr/share/doc/cgroup-tools/examples/cgred.conf /etc/sysconfig/cgred.conf
```

#### libcgroup configuration ~ cgconfig.conf

The `/etc/cgconfig.conf` configuration file serves as a structured means of declaring `cgroup` parameters and mount points. Further information for particular sections of the configuration file can be found with: `man cgconfig.conf`. Enabling `unprivileged containers` is done as follows:
   ```bash
   group username_here {
     perm {
       task {
         uid = username_here;
         gid = username_here;
       }
       admin {
         uid = username_here;
         gid = username_here;
       }
     }
     
     # All controllers available in 3.16.0-4
     # Listed by running: cat /proc/cgroups
     cpu {}
     blkio {}
     cpuacct {}
     cpuset {
       cgroup.clone_children = 1;
       cpuset.mems = 0;
       cpuset.cpus = 0-3;
     }
     devices {}
     freezer {}
     perf_event {}
     net_cls {}
     net_prio {}
   
     # The memory controller is not enabled by default in Debian Jessie despite being enabled in the kernel
     # If you enable it add the following
     memory { memory.use_hierarchy = 1; }
   }
   ```
Quite a bit is going on with the configuration file above so i'll try and explain what is happening:

* `group username_here {`: Define a control group called "username_here" (can be named anything that adheres to directory naming conventions) that encompasses the `permissions` and subsequent `task` and `admin` children stanzas.  
Notice the kernel subsystem controllers further down the file: `cpu {}`, `blkio {}`, etc. By including these we tell the `cgrulesengd` daemon that we wish our `cgroup` to be governed by these subsystem "controllers". 
This results in the creation of a "username_here" directory within the mounted cgroups virtual filesystem underneath each declared subsystem: `/sys/fs/cgroup/[subsystem]/username_here`. 

* `perm {` : Permissions to _use_ and _alter_ the `cgroup` are assigned to a UID and GID in the _task_ (`task {`) and _admin_ (`admin {`) child stanzas respectively. 
The `task` UID/GID owns the `/sys/fs/cgroup/[subsystem]/username_here/tasks` file, which is in itself a simple list containing PIDs of all processes in currently running within that control group.
The `admin` UID/GID owns the remaining files within the control group.

* `cpuset {`:
    - `cgroup.clone_children = 1;`: Summarised by the official Cgroups kernel documentation (<a href="https://www.kernel.org/doc/Documentation/cgroups/cgroups.txt">here</a>) as: 
> "This flag only affects the `cpuset` controller. If the `clone_children` flag is enabled (1) in a cgroup, a new cpuset cgroup will copy its configuration from the parent during initialization."

    - `cpuset.mems = 0;`: Specifies the memory nodes from a NUMA perspective that processes under this control group can access. Only applies to systems using NUMA where memory (RAM) nodes are assigned to particular processors. The number of NUMA nodes can be determined by outputting the kernel's "buddyinfo" details `cat /proc/buddyinfo`. 
This option is _mandatory_ for the cpuset subsystem to function correctly.  

    - `cpuset.cpus = 0-3;`: Specifies the CPUs tasks within the `cgroup` are allowed to execute upon. The number of available CPUs can be listed via the 'lscpu' command: `lscpu | grep ^On-line`.
This option is _mandatory_ for the cpuset subsystem to function correctly.  

Further information (e.g. file/directory permissions) in addition to some realistic examples can be found in the man pages (`man cgconfig.conf`). The aim here is to create a _minimum viable product_ for successfully deploying LXC `unprivileged containers`.

#### libcgroup configuration ~ cgrules.conf

The `/etc/cgrules.conf` configuration file is read by the `cgrulesengd` daemon in order to determine which `cgroup` a process belongs to as well as its destination:
```bash
# <user>:<process_name>  <controllers> <destination>
username_here   *        username_here
```
The configuration layout above can be interpreted as:
> All processes started by "username_here" for all listed "controllers" (in `/etc/cgconfig.conf`) belong to the control group called "username_here"

### Configure cgconfigparser

While the `cgrulesengd` daemon handles the automatic distribution of processes to their corresponding `cgroup` (and consequential cloning of parent control group files) based off the rules present in the `/etc/cgrules.conf` file, the creation of the control group directory "username_here" for each subsystem controller (e.g. `/sys/fs/cgroups/{cpu,blkio,devices,...}/username_here/` is performed by the `cgconfigparser` utility. 

The `cgconfigparser` utility _must_ successfully read the `/etc/cgconfig.conf` file and populate the necessary controller directories before the `cgrulesengd` daemon is started. To achieve this I copied the systemd service file `cgconfig.service` found in the Fedora 20 GNU/Linux distribution (<a href="http://www.crashcourse.ca/wiki/index.php/RH_cgroups#cgconfig.service">here</a>) and saved it under `/lib/systemd/system/cgconfig.service`:
```bash
[Unit]
Description=Control Group configuration service

# The service should be able to start as soon as possible,
# before any 'normal' services:
DefaultDependencies=no
Conflicts=shutdown.target
Before=basic.target shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/cgconfigparser -l /etc/cgconfig.conf -s 1664
ExecStop=/usr/sbin/cgclear -l /etc/cgconfig.conf -e

[Install]
WantedBy=sysinit.target
```

> Be careful when using the `/usr/sbin/cgclear` utility manually, if you omit the "load configuration file" flag (`-l`) you will remove the preexisting systemd control groups hierarchy from the running session. I'm unsure how to go about reverting this operation without restarting the host. 
{: .prompt-warning }

> To avoid this ensure you always use "load configuration file" flag (`-l`) to remove just the control groups configured or follow the instructions presented `/usr/share/docs/cgroup-tools/README_systemd` for compiling `libcgroup` with the option to purposefully ignore the 'name=systemd' hierarchy. 
{: .prompt-info }

1. To ensure the `cgconfigparser` utility is started at boot time we need to _enable_ the systemd service file:
```bash
sudo systemctl enable cgconfig
```

2. Start the "oneshot" `cgconfig.service` systemd service file that will create the required control group directories under the previously specified subsystem controllers (e.g. `/sys/fs/cgroups/{cpu,blkio,devices,...}/username_here/`):
```bash
sudo systemctl start cgconfig
```

3. Confirm that the "username_here" `cgroup` exists:
```bash
    lscgroup
    
    # desirable result
    cpu,cpuacct:/
    cpu,cpuacct:/username_here
    devices:/
    devices:/username_here
```

### systemd services ~ cgrulesengd

1. Create a systemd service file `/lib/systemd/system/cgred.service` for the `cgrulesengd` daemon. Again, I have used the Fedora 20 GNU/Linux distribution template `cgred.service` service file (<a href="http://www.crashcourse.ca/wiki/index.php/RH_cgroups#cgred.service">here</a>):
```bash
    [Unit]
    Description=CGroups Rules Engine Daemon
    After=syslog.target
    
    [Service]
    Type=forking
    EnvironmentFile=-/etc/sysconfig/cgred.conf
    ExecStart=/usr/sbin/cgrulesengd $OPTIONS
    
    [Install]
    WantedBy=multi-user.target
```

2. Enable the `cgred.service` to ensure that the `cgrulesengd` daemon starts at boot:
```bash
sudo systemctl enable cgred
```

3. Start the `cgrulesengd` daemon via systemd:
```bash
sudo systemctl start cgred
```
  
4. Check that new processes are being moved to the user defined control group "username_here" by outputting the contents of `/sys/fs/cgroup/[subsystem]/username_here/tasks` file:
```bash
cat /sys/fs/cgroup/[subsystem]/username_here/tasks
```

You should be seeing a list of PID values assuming the `cgrulesengd` daemon is running correctly and has migrated the existing `$USER` processes to the appropriate `cgroup` within each subsystem controller.

##### Debugging

If nothing has happened try invoking a new process (e.g. open up an interactive application) and then check the `tasks` file of any of the subsystems (the subsystem does _not_ matter as we told the `cgrulesengd` daemon to use the `cgroup` "username_here" for all available subsystems in the `/etc/cgconfig.conf` file).
If tasks are still not showing up then stop the `cgrulesengd` daemon with `sudo systemctl stop cgred` and invoke it manually in the foreground with high verbosity (includes logging to `/var/log/syslog.log`):
```bash
sudo cgrulesengd -n -vvv -s
```
Examine the output of the daemon on a live basis by "tailing" the end of the `syslog.log` file: `sudo tail -f /var/log/syslog.log`

## Creating an unprivileged container

Assuming all previous steps have been successfully followed (without any errors!) we have now configured the host environment sufficiently enough to support the creation and execution of `unprivileged containers`.

The various limitations imposed by `user namespaces` (i.e. disallowed loop/filesystem mounts and forbidden usage of `mknod`) mean that traditional LXC templates (located at: `/usr/share/lxc/templates/lxc-*`) used for creating privileged containers will (most likely*) fail when invoked by an _unprivileged_ user. 

With different GNU/Linux distributions each having their own particular LXC-specific bootstrapping mechanism (as dictated by their corresponding template script) Stéphane Graber constructed a new template, "download", which alleviates the requirement of understanding distro-specific bootstrapping mechanisms by permitting the download of various daily pre-built GNU/Linux distribution `rootfs` that have been specially configured to operate within a restricted _unprivileged container_.

Opening up the "download" LXC template script (`/usr/share/lxc/templates/lxc-download`) reveals that the daily pre-built `rootfs` are downloaded (securely via GPG where possible) from the webserver `images.linuxcontainers.org` (as declared by the `DOWNLOAD_SERVER` Bash variable). 
Beyond this, the "download" template selects the corresponding menu metadata list `images.linuxcontainers.org/meta/1.0/index-$DOWNLOAD_COMPAT_LEVEL` for allowing the user to download either _unprivileged_ or privileged container `rootfs` depending on the execution environment the template determines to be in; for example if the script was executed by root it then lists the corresponding privileged container `rootfs` offerings.

By default the "download" template included with the `lxc` package (1:1.0.6-6+deb8u1) for Debian Jessie 8.2 has a variable set, `DOWNLOAD_COMPAT_LEVEL=1` , that results in a reduced offering of pre-built GNU/Linux distributions (i.e. older releases of distributions, no Debian 8) suitable for the restricted `unprivileged container` environment. This variable results in the script downloading and parsing the metadata menu file `https://images.linuxcontainers.org/meta/1.0/index-user.1` as opposed to the "fuller" `https://images.linuxcontainers.org/meta/1.0/index-user` metadata menu file. 

By explicitly unsetting the `DOWNLOAD_COMPAT_LEVEL` variable (e.g. `DOWNLOAD_COMPAT_LEVEL=`) the "download" template will obtain the more complete GNU/Linux distribution list for the `unprivileged container` environment. 

> Expect breakages/failures when overriding `DOWNLOAD_COMPAT_LEVEL`
{: .prompt-warning }

Having personally tried editing the `DOWNLOAD_COMPAT_LEVEL` variable within Debian Jessie 8.2 in an effort to download a Debian Jessie `rootfs` suitable for the `unprivileged container` environment I was faced with the single line error: 
> Failed to mount cgroup at /sys/fs/cgroup/systemd: Operation not permitted.

Several other individuals attempting a Debian Jessie deployment in an `unprivileged container` environment have also encountered this issue; Thomas Dalichow isolated the <a href="http://comments.gmane.org/gmane.linux.kernel.containers.lxc.general/9557">problem </a>) to an older `systemd` version running by default on Debian Jessie 8.2 (215-17+deb8u2). 
Thomas did mention however that the version of systemd released by the testing branch of Debian ("Stretch") which, at his time of posting was 220-5 (it is now currently at 226-3), worked correctly with the various `unprivileged container` `rootfs` that were linked to by the `https://images.linuxcontainers.org/meta/1.0/index-user` metadata menu file.

1. Create an `unprivileged` Debian "Wheezy" amd64 container via the provided "download" template:
```bash
# Performed as an unprivileged user
lxc-create --name my_unprivileged_container \
              --template download -- \
              --dist debian \
              --release wheezy \
              --arch amd64
```

    > Omitting one or more of the three platform options (`'--dist'`, `'--release'`, or `'--arch'`) will invoke a basic interactive mode that will list available templates using any of the supplied flags as a simple filter. Passing no platform flags will result in all the distribution platforms being listed and interactively prompted. 
    {: .prompt-info }
LXC downloads (and caches) the `rootfs` of the Debian "Wheezy" amd64 based `unprivileged container` preparing it for usage. The `rootfs` "image" is stored at: `~/.cache/lxc/download/debian/wheezy/amd64

2. As there are no preconfigured users and the `root` user has `not` been assigned a password (for security purposes) start the `unprivileged container` as a daemon:
```bash
lxc-start --name my_unprivileged_container \
             --daemon
```

3. Set the `root` user password via `lxc-attach`:
```bash
lxc-attach --name my_unprivileged_container -- passwd
```

4. Login to the `unprivileged container` as the `root` user via the standard `getty` interative login shell:
```bash
lxc-console --name my_unprivileged_container
```
    > Press <kbd>ctrl-a, q</kbd> to exit the `unprivileged container` console and return back to the host's console.
    {: .prompt-info }

If all has worked now and you are logged into your `unprivileged container` as the `root` user then congratulations your environment has been configured correctly! 

If you are facing issues at this stage try running the container _without_ the `--daemon` flag and examine the output produced. A series of links I find helpful in the "credits" section at the bottom of this page may be of help to resolve your particular issue.

## Governing network access

Thankfully the process for configuring network access for `unprivileged containers` is identical to privileged containers with the exception of one particular aspect: 
> Unlike privileged containers, a dedicated system-wide configuration file: `/etc/lxc/lxc-usernet`, is required to limit the amount of "veth" pairs that an unprivileged user can create as well as the network bridges that the user can connect to.

1. Create the system-wide LXC configuration file: `/etc/lxc/lxc-usernet`, that governs network access for `unprivileged containers`. For example lets say we limit user "username_here" to only access the _bridge_ `lxcbr0` with a maximum of **2** "veth" pairs.
```bash
# <user>       <link_type>  <bridge>  <#_of_links>
username_here  veth         lxcbr0     2
```
    > Omit the field headers line when creating the `/etc/lxc/lxc-usernet` configuration file; It simply serves an an explanation aid.
    {: .prompt-info }

2. Stop the `unprivileged container` targeted for network access then do so now:
```bash
lxc-stop --name my_unprivileged_container
```

3. Edit the targeted `unprivileged container`'s configuration file (e.g. `~/.config/share/lxc/my_unprivileged_container/config`) and append the following network configuration:
```bash
lxc.network.type = veth
lxc.network.link = lxcbr0
lxc.network.flags = up
```
This minimal network configuration will provide the `unprivileged container` with network access to the bridge `lxcbr0`.

4. Start the `unprivileged container` and check that it has internet access by updating APT (assuming the network that _bridge_ `lxcbr0` is connected to has DHCP preconfigured, external internet connectivity, and a functional DNS resolver):
```bash
   # Start
lxc-start --name my_unprivileged_container \
             --daemon

   # Update APT cache
lxc-attach --name my_unprivileged_container -- apt-get update
```
 
## Final Words

The configuration presented here will place all user owned processes into their own control group but it will _not_ apply any sort of hardware resource restrictions (as evident from the `/etc/cgconfig.conf` file). This means that sub-control groups can be employed (with varying, granular resource restrictions if desired), they will just be nested under the "username_here" group (e.g. `/sys/fs/cgroup/[subsystem]/username_here/subgroup_name/`).

By creating the `cgconfig.service` and `cgred.service` systemd service files the environment for enabling the creation and execution of `unprivileged containers` will persist between reboots.   

> This guide blog post was written via an Iceweasel browser **running inside** an `unprivileged container` on: Linux Debian-Jessie 3.16-0-4-amd64 #1 SMP Debian 3.16.7-ckt11-1+deb8u3 (2015-08-04) x86_64 GNU/Linux. 
{: .prompt-tip }

If you've spotted any mistakes/typos I've made or you'd like to comment/question any aspect feel free to leave a response in the comment box below.

## Credits

A wide range of web sources were used to understand how to go about configuring `unprivileged containers` in Debian Jessie 8.2. If my troubleshooting tips have not resolved any issues you faced from following this guide (apologies in advance!) than these links/man pages may serve to remedy your situation:

* https://www.stgraber.org/2014/01/17/lxc-1-0-unprivileged-containers/
* http://unix.stackexchange.com/questions/170998/how-to-create-user-cgroups-with-systemd
* https://wiki.archlinux.org/index.php/Cgroups
* https://access.redhat.com/documentation/en-US/Red\_Hat\_Enterprise\_Linux/6/html/Resource\_Management\_Guide/ch-Using\_Control\_Groups.html
* man cgconfig.conf
* man cgrules.conf
* man cgconfigparser
* man cgrulesengd

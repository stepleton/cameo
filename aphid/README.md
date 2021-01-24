# Cameo/Aphid

![A PocketBeagle/Cameo stack with a connector attached](pics/cameo-aphid.jpg)

is a small Apple parallel port hard drive emulator based on the
[PocketBeagle](http://beagleboard.org/pocket) single-board computer and the
[Cameo](../README.md) 3.3V ⇄ 5V level adaptor cape. The hardware and software
described here aim to be a substitute for 5MB Apple
[ProFile](https://en.wikipedia.org/wiki/Apple_ProFile) external hard drives,
which were mainly used with Apple /// and Apple Lisa computers.

## Fair warning

Cameo/Aphid and associated hardware designs, software materials, and other
resources distributed alongside it are all made available for free with NO
WARRANTY OF ANY KIND. Any system that interfaces with Cameo/Aphid could suffer
malfunction, data loss, physical damage, or other harms. Some of these effects
could be permanent and/or unrepairable. If you're not prepared to risk these
consequences, don't use Cameo/Aphid.

**Additionally**: Cameo/Aphid is a new design that incorporates a number of
brand new, built-from-scratch software and hardware components. Although
considerable effort has been made to build a dependable emulator, Cameo/Aphid
still faces the test of time. It is possible, even likely, that some subtle
bugs have yet to be discovered and fixed.

## Gallery

Thumbnails link to high-resolution images, which may be helpful to people
assembling Cameo/Aphid. These images are not claimed to be illustrative of
good soldering technique.

[![Major Cameo/Aphid hardware components](pics/thumb_all_parts.jpg)
Top and bottom views: PocketBeagle, Cameo, 5V I/O header to DB-25 adaptor.](
https://photos.app.goo.gl/s5zESxhNN7xtycam7)

[![Cameo/Aphid hardware angled front and back views](pics/thumb_frontback.jpg)
Angled front and back views: Cameo/Aphid hardware components.](
https://photos.app.goo.gl/JWuywM5HkStonCPk9)

[![Cameo/Aphid hardware angled side views](pics/thumb_sideside.jpg)
Angled side views: Cameo/Aphid hardware components.](
https://photos.app.goo.gl/5HDvheUgoSHjGmFy6)

[![Cameo/Aphid hardware on a Lisa, profile view](pics/thumb_profile.jpg)
Profile view: Cameo/Aphid hardware installed on an Apple Lisa computer.](
https://photos.app.goo.gl/Pqm4weZKrUjdkRwC8)

A few additional photos are available in a [Google Images gallery](
https://photos.app.goo.gl/dgnkZrpXCz5ze1h9A).

## Usage

Cameo/Aphid is designed to be used in much the same way as a real ProFile hard
drive: it must be on and ready before the computer can be used; once the
computer is off again, Cameo/Aphid can be shut down and turned off.

Because Cameo/Aphid is based on the PocketBeagle, a single-board computer that
must boot an operating system to function, Cameo/Aphid takes longer to become
ready than a dedicated hardware emulator (e.g.
[X/ProFile](http://sigmasevensystems.com/xprofile), [IDEfile](
http://john.ccac.rwth-aachen.de:8000/patrick/idefile.htm)) does. Additionally,
like any modern computer (including the Apple Lisa), Cameo/Aphid prefers to
undergo a shutdown process before power is shut off.  To accomplish this at any
point after Cameo/Aphid is ready, press the [power button](
https://github.com/beagleboard/pocketbeagle/wiki/System-Reference-Manual#333_Powering_Down)
and wait for the "chasing lights" pattern (see below) to stop. It should only
take a few seconds.

(Full shutdown is not as important on Debian 9.5 and later OS releases, as long
as all the optional steps in the [installation instructions](
#full-instructions-for-manual-software-installation) have been carried out.
The [pre-made SD card image](#software-installation) was made in this way.
Robustness to power cuts is one step toward making Cameo/Aphid a suitable
replacement for Widget internal hard drives, though [other hurdles](
#future-work) remain.)

![Locations of the User LEDs and power button on the PocketBeagle](pics/ui.jpg)

Cameo/Aphid uses the four "user LEDs" on the PocketBeagle to provide a visual
indication of its state. The light patterns you are most likely to see are
these:

1. **Just after Cameo/Aphid turns on**: The LEDs turn on one-by-one until all
   four are on.
2. **While the operating system is booting**: One LED is on nearly constantly,
   another blinks in a "heartbeat" rhythm; a third blinks with SD card access.
3. **While Cameo/Aphid software is starting up**: All four LEDs blink
   sequentially in a rapid "chasing" or "rotating" pattern.
4. **When Cameo/Aphid is ready**: All four LEDs are on constantly.
5. **When Cameo/Aphid processes a disk command from the Apple**: All four LEDs
   blink off momentarily.
6. **During the shutdown process**: The chasing pattern resumes.
7. **When Cameo/Aphid is ready for power off**: The chasing pattern has frozen;
   at most one LED is on.

Finally, if Cameo/Aphid has encountered an unrecoverable error, the two central
user LEDs will slowly blink on and off. If this happens, try shutting down the
device by pressing the power button. Once the blinking stops, or if the power
button appears to have no effect after some time, try removing power from
Cameo/Aphid and then restoring it.

### Physical connections

Cameo/Aphid receives power from an ordinary Micro-B USB cable. Power
consumption data is hard to find for the PocketBeagle, but just about any USB
power source that can charge a phone reasonably well will probably work. A
computer with a USB-A port can supply power as well; don't be surprised by the
PocketBeagle's operating system making the PocketBeagle appear to be both a
network adaptor and a storage device.

Most installations will connect Cameo/Aphid to the Apple via a short adaptor
cable like the one described in the [main Cameo README.md](
../README.md#assembly). In this configuration, Cameo/Aphid dangles from the
Apple's DB-25 socket with no enclosure or physical support. If your Apple is
installed on an unpainted metal table or rack, take care that no components or
solder joints on the PocketBeagle or Cameo circuit boards rest on any metal
surface: stray electrical connections could result.

### Hard drive images

Cameo/Aphid stores data from the simulated hard drive in an ordinary file on
the PocketBeagle's microSD card. This file has no metadata and a very simple
format: just as a ProFile stores 5,175,296 bytes of data, the hard drive image
file is a 5,175,296-byte file; and just as a ProFile block is 532 bytes, each
contiguous 532-byte chunk of the image file holds data from one of the
simulated drive's blocks. These blocks are arranged sequentially in the file,
starting from block $0000 and counting up to block $25FF.

(Aside: neither Cameo/Aphid nor the Apple parallel hard disk protocol itself
distinguish between "tag bytes" or "data bytes", even though these divisions of
a block are important to Lisas.)

A microSD card initialised from the [pre-built software image](
#software-installation), or any other installation that makes use of a
[separate FAT32 partition for drive image storage](
#4-optional-prepare-a-separate-partition-for-cameoaphid-drive-images), can be
plugged into most modern computers and accessed like an ordinary flash drive.
Some computers may show two drives, one called `rootfs` and another called
`CAMEO_APHID`: the `CAMEO_APHID` drive is the home for hard drive images, and
`rootfs` should be left alone. (Windows users who don't see a drive after
plugging in their microSD cards may need to use the "Disk Management" or
"Create and format hard disk partitions" control panel to assign a drive letter
to the SD card's `CAMEO_APHID` partition.)

On the `CAMEO_APHID` drive, hard drive image files are any that end in
`.image`, with `profile.image` being the image file that Cameo/Aphid uses on
start-up.  It is fine to copy, rename, and otherwise manage hard drive image
files like any other kind of file, but Cameo/Aphid will not work if no file
called `profile.image` exists.

The operating system that runs on Cameo/Aphid's PocketBeagle computer is a
version of Debian Linux. In standard Cameo/Aphid setups, the `CAMEO_APHID`
partition is mounted at `/usr/local/lib/cameo-aphid`. If you have a network
connection to the PocketBeagle, which usually establishes automatically when
you plug a PocketBeagle into a modern computer's USB port, you can use ordinary
communications utilities (typically SSH, SCP) for command line access and file
transfer with the device. (For more guidance on connecting to your
PocketBeagle, see the [BeagleBone "Getting Started" guide](
http://beagleboard.org/getting-started). You may need to use the IP addresses
192.168.6.2 or 192.168.7.2 instead of the `beaglebone.local` convenience name.)

In the future, it may become possible to upload and download disk images via a
web browser.

:warning: **Be sure not to change or replace the hard drive image file while
the Apple is actively reading from or writing to the simulated disk drive.
After altering the image file, you must shut down and restart Cameo/Aphid
before the Apple attempts to access the drive.**

### For programmers

Cameo/Aphid allows the Apple to restart or shut down ProFile emulation via
specially-formatted writes. The Apple can use this "control writes" mechanism
to change the hard drive image file that Cameo/Aphid uses for reads and writes.

The following "control writes" are made to the non-existent sector $FFFFFD,
with $FE as the retry count parameter and $AF as the sparing threshold
parameter:

- Writing sector data that begins with the null-terminated string "HALT" (i.e.
  `$48,$41,$4C,$54,$00`) causes Cameo/Aphid to cease ProFile emulation. This
  does not shut down the PocketBeagle itself. When emulation is halted, the
  four user LEDs will blink sequentially in a rapid "chasing" or "rotating"
  pattern.

- Writing sector data that begins with "IMAGE:" (i.e. `$49,$4D,$41,$47,$45,$3A`)
  and then continues with the null-terminated name of a file residing in the
  working directory of the Cameo/Aphid ProFile emulator Python program, causes
  Cameo/Aphid to restart ProFile emulation with this file as the hard drive
  image that it uses for reads and writes. For extra safety, the filename must
  end in ".image".

- Writing any other sector data will cause Cameo/Aphid to restart ProFile
  emulation with the same hard drive image file that it was using prior to the
  write.

Restarting ProFile emulation takes less than a second, but no effort has been
made to determine what happens if the Apple tries to interact with Cameo/Aphid
during this interval.

## Making your own

At present, the only way to get your own Cameo/Aphid is to build one. Finished
assemblies are not known to be available anywhere, but since all the
Cameo/Aphid-specific software and hardware designs are released into the public
domain, anyone is free to build and sell them without seeking anyone's
permission or negotiating any license terms. The parts cost for a complete,
ready-to-use Cameo/Aphid setup is around $55 for a home hobbyist; manufacture
in limited quantities might lower this figure somewhat.

Building Cameo/Aphid "from scratch" requires some proficiency in the following
skills:

* Soldering surface-mounted components, including ICs in small (TSSOP) packages
  with a somewhat narrow (0.65mm) pin pitch.
* ~~"Linux stuff": SSH, using the command line, `sudo`, editing configuration
  files, that sort of thing.~~

If you think you *might* be able to do it, you probably can, with patience.

### Hardware assembly

Cameo/Aphid uses the Texas Instruments [TXS0108E](
http://www.ti.com/product/TXS0108E) series of level translator ICs. A complete
parts list for assembling Cameo/Aphid appears in the [main Cameo README.md](
../README.md#costs). Nearly all installations will want to use the short
adaptor cable described there so that Cameo/Aphid can dangle from a parallel
port on the Apple.

This diagram shows the locations and values of all of the SMD components that
should be installed on the Cameo PCB to support Aphid:

![All surface mount components for Cameo/Aphid](pics/smd_layout.png)

The jumpers on the "plugboard" pads establish connections between the 5V I/O
header pins and the level translator chip. The current design uses 100Ω
terminating resistors for these connections to support longer cables between
Cameo/Aphid and the Apple; in general, though, shorter cables are preferable.
Take care to replicate the positioning of all components exactly---the
plugboard pads are tightly spaced, and it's especially easy to put a jumper in
the wrong place.

The [main Cameo README.md](../README.md#assembly) has more detailed assembly
information.

When building a DB-25 port adaptor to connect Cameo to the Apple: sometimes the
Apple's parallel port will have plastic material or a metal shim blocking pin
7, which is unused. If this is the case for your system, remove pin 7 (the
centre pin in the top, wider row of pins) from the adaptor's DB-25 plug with a
pair of pliers. Some force may be required.

### Software installation

The easiest way to install Cameo/Aphid software on a microSD card is to "flash"
a pre-built software image onto the card: it requires no skill with "Linux
stuff". Download a software image (made with the instructions below) from [this
link](http://stepleton.com/cameo_aphid_image.php) (note: a circa 600 MB file,
give or take several dozen MB), then follow [these instructions](
https://beagleboard.org/getting-started#update) on using Etcher to install the
image onto a good quality microSD card (4GB or more, preferably [Class
10/U1/V10](https://en.wikipedia.org/wiki/Secure_Digital#Speed_class_rating) or
better).  Once flashed, the card can be plugged into the PocketBeagle, and
Cameo/Aphid will be ready for [use](#usage), appearing to the Apple as an empty
(uninitialised) ProFile. The following instructions can then be ignored.

(Technical note: The pre-built software image stores the ProFile disk image on
a separate 512 MB FAT32 partition with the label `CAMEO_APHID`, which it mounts
at `/usr/local/lib/cameo-aphid`. Only changes to files in this directory will
persist between PocketBeagle power cycles and reboots; all changes to all other
files and directories are temporary.)

#### Full instructions for manual software installation

The Cameo/Aphid software comprises

* firmware programs for each of the PocketBeagle's two PRU-ICSS real time
  I/O coprocessors ("PRUs" for short)
* a [Python program](profile.py) that runs on the PocketBeagle's main
  processor, interpreting sector read/write commands from the Apple and
  applying them to a hard drive image file
* a [Python plugin module](profile_plugins.py) for the program that provides a
  "magic blocks" facility: reads and writes to these blocks can modify the
  behaviour of the emulator or support a variety of operations unrelated to
  ordinary hard drive data storage
* a collection of Python module plugins that exploit this capability to provide
  a [system information service](profile_plugin_FFFEFD_system_info.py), a
  [file management service](profile_plugin_FFFEFE_filesystem_ops.py), and a
  [key/value store](profile_plugin_FFFEFF_key_value_store.py)
* a [software program for the Apple Lisa](selector), taking the form of a
  bootable hard drive image, that uses the "magic block" plugins to provide a
  versatile text-based interface for selecting and managing hard drive images.

The software targets the following BeagleBone.org Debian Linux disk images:

* `Debian 10.3 2020-04-06 4GB SD IoT` **(Not recommended: see below)**
* `Debian 10.0 2019-07-07 4GB SD IoT`
* `Debian 9.9 2019-08-03 4GB SD IoT`
* `Debian 9.5 2018-10-07 4GB SD IoT`
* `Debian 9.5 2018-08-30 4GB SD IoT`
* `Debian 9.4 2018-06-17 4GB SD IoT`
* `Debian 9.3 2018-03-05 4GB SD IoT`

available [here](http://beagleboard.org/latest-images). If none of these are
listed under "Recommended Debian images", look for them under "Older Debian
images" further down on the page. Newer images may work but have not been
tested.

(The `Debian 10.3 2020-04-06 4GB SD IoT` image is not recommended as it lacks
support for the optional [power-off robustness mechanism](
#8-optional-enable-power-off-robustness-for-the-root-filesystem) described
below. [A feature request](
https://github.com/beagleboard/Latest-Images/issues/80) to restore this support
in future BeagleBone.org Debian Linux disk images has been filed.)

Follow these steps to set up the Cameo/Aphid software on your PocketBeagle:

#### 1. Install the Linux disk image onto a new microSD card.

Download one of the Debian Linux disk images specified above from the
BeagleBoard.org [Latest Firmware Images](http://beagleboard.org/latest-images)
page (preferably the Debian 9.9 image). Follow the [instructions](
https://beagleboard.org/getting-started#update) to install it on a good quality
microSD card. (The PocketBeagle used to develop the Cameo/Aphid software had a
card with a Class 10 [speed class rating](
https://en.wikipedia.org/wiki/Secure_Digital#Speed_class_rating).)

#### 2. Enable remoteproc/RPMsg for controlling the PocketBeagle's PRUs (Debian 9.3 only).

:warning: **NOTE: This step is only required for the `Debian 9.3 2018-03-05 4GB
SD IoT` Debian Linux disk image.**

Boot your PocketBeagle and connect to it via SSH. As above, this usually
entails plugging the PocketBeagle into your computer's USB port and logging in
to `beaglebone.local` as user `debian` with password `temppwd`. For more
guidance on connecting to your PocketBeagle, see the [BeagleBone "Getting
Started" guide](http://beagleboard.org/getting-started).

Once in, edit the file `/boot/uEnv.txt` with superuser privileges. Find the
line containing this text:

    #uboot_overlay_pru=/lib/firmware/AM335X-PRU-UIO-00A0.dtbo

and just beneath it, add a new line with the following text:

    uboot_overlay_pru=/lib/firmware/AM335X-PRU-RPROC-4-9-TI-00A0.dtbo

Take care to avoid typos or copy/paste errors: mistakes in `/boot/uEnv.txt` can
leave your microSD card unbootable, and you'd need to start over from Step 1.

#### 3. Compile the firmware and prepare an empty 5MB disk image.

Copy this directory and all of its contents to the PocketBeagle (usually
accomplished via SCP to `beaglebone.local`). It's fine to place the copy
anywhere in the home directory of the `debian` user.

Log back into your PocketBeagle and cd into the copy of this directory. Begin
the compile by typing `make`. Compilation of the firmware and construction of
the disk image (which is just an empty 5,175,296-byte file called
`profile.image`) takes a couple dozen seconds.

#### 4. (optional) Prepare a separate partition for Cameo/Aphid drive images.

This optional step establishes a separate FAT32 partition on the SD card for
ProFile disk image storage---required for setting up the robustness to power
failure described in Step 8. First, from the directory created by Step 3,
execute the script `setup_dos_partition_part1.sh` with superuser privileges,
optionally with a size argument in bytes (a 512 MB partition is created by
default). When this completes, reboot the PocketBeagle. Log in again, return to
the same directory, and execute the script `setup_dos_partition_part2.sh`.

Together, these scripts modify the SD card's partition table to add a
partition, create a mount point for the partition at
`/usr/local/lib/cameo-aphid`, create a FAT32 filesystem on the partition, and
direct the OS to mount the new partition there on boot.

#### 5. Install the Aphid software, firmware, disk image, and service script.

From the directory created by Step 3, execute the command `make install` with
superuser privileges. This command creates a permanent installation directory
for the Cameo/Aphid software and disk image, then installs a file that tells
the PocketBeagle to configure and start the entire Cameo/Aphid emulator system
on boot. The specific steps that `make install` performs are:

- Copy the PRU-ICSS firmware files `aphd_pru0_datapump.fw` and
  `aphd_pru1_control.fw` to the `/lib/firmware` directory.
- Create the directory `/usr/local/lib/cameo-aphid` (if not already present)
  and copy the disk image file `profile.image` and the Python program
  `profile.py` inside.
- Copy the `cameo-aphid.service` service script to `/lib/systemd/system`.

#### 6. Tell the PocketBeagle to start the Cameo/Aphid emulator system on boot.

With superuser privileges, execute the command `systemctl enable cameo-aphid`.

Basic software installation is complete after this step. The next time the
PocketBeagle boots, the Cameo/Aphid emulator should be ready to emulate a 5 MB
Apple ProFile hard drive. See the [Usage](#usage) section of this file for
usage instructions.

The following steps are optional, but useful.

#### 7. (optional) Disable unneeded Linux system facilities.

With superuser privileges, and in the directory created by Step 3, run the
scripts `setup_trim_services.sh` and `setup_trim_misc.sh`. This disables some
PocketBeagle system facilities that aren't useful for hard disk emulation,
which shaves a few seconds off the time it takes Cameo/Aphid to be ready after
power-on.

#### 8. (optional) Enable power-off robustness for the root filesystem.

Only if Step 5 has been carried out, run the script `setup_overlayroot.sh` with
superuser privileges. This causes the PocketBeagle to boot into a mode where
files on the root filesystem cannot be changed; instead, changes are stored
temporarily in the PocketBeagle's RAM and are lost when the PocketBeagle shuts
down or reboots. The separate filesystem for disk images set up in Step 5 is
not affected and writes to emulated ProFiles will still be saved.

This step makes it safer to shut off power to Cameo/Aphid without undergoing
the formal shutdown process triggered by pressing the power button. The root
filesystem cannot be damaged by uncommitted writes, and changes to the FAT32
filesystem containing disk image data are frequently committed to the SD card.

## Technical overview

The information in this section is not necessary to build or use Cameo/Aphid,
but may be of interest to people interested in making modifications or
investigating similar applications.

Cameo/Aphid takes advantage of the PocketBeagle's [PRU-ICSS coprocessors](
http://processors.wiki.ti.com/index.php/PRU-ICSS) ("PRUs" for short) to achieve
a dependable implementation of the Apple parallel port hard drive protocol.
Like the I/O subsystems on modern PCs or the [channel controllers](
https://en.wikipedia.org/wiki/Channel_I/O) on mainframes of yore, the PRUs
handle the timing-sensitive low-level details of the protocol so that the main
processor can attend to various custodial tasks on its own schedule.

The PocketBeagle's [AM3358 SoC](http://www.ti.com/product/AM3358) includes two
PRUs. Each PRU has a different pattern of direct connectivity to the pins of
the PocketBeagle's two expansion headers. PRU 0 can access eight pins in either
the input or output direction plus four more as inputs only and two more as
outputs only; PRU 1 can access six pins in either the input or output direction
plus two more as inputs only. Cameo's pair of level translator ICs can
accommodate only 16 signal lines altogether, so of these 22 pins, Cameo passes
through all 14 two-way signals, one PRU 0 input-only line, and one PRU 0
output-only line.

Inspired by this arrangement and the nature of the Apple parallel port hard
drive protocol, the overall Cameo/Aphid design allocates PRU 0 to handle
clocked data transfer and calculation of the (odd) parity signal for the
parallel port's eight bidirectional I/O lines, and it allocates PRU 1 to handle
the parallel port's three other control lines. Notionally, PRU 1 supervises the
handling of all transactions with the Apple; PRU 0 is the "data pump" that
streams bytes to and from the Apple on PRU 1's request, while the Python
program running on the PocketBeagle's main ARM processor loads and saves block
data in the disk image file whenever PRU 1 instructs it to do so.

Although PRU 0 can directly access eight of the I/O pins as either inputs or
outputs, a PRU cannot select or change which of these "direct access" modes is
in effect. Unfortunately, that means that these modes aren't suitable for
bidirectional I/O, even though Cameo is otherwise well-organised to facilitate
this: PRU 0 simply can't alternate between sending and receiving data via
direct access. So, to manage the eight data lines, PRU 0 falls back to using
the AM3358's GPIO registers---a method available to either PRU. Still, the
division of labour between both PRUs is convenient: it allows PRU 0 to respond
quickly to the Apple's \PSTRB clocking signal and to compute the correct value
for \PPARITY (both accessed by PRU 0 directly) whilst PRU 1 and the ARM are
busy doing other things.

PRU 0 and PRU 1 do most of their information sharing through the PRU shared
memory region, with data transfer requests and completions signaled via
interrupts. Communication between PRU 1 and the ARM uses Linux's [RPMsg](
https://www.kernel.org/doc/Documentation/rpmsg.txt) I/O framework, and because
RPMsg messages can be no larger than 512 bytes, multiple messages are necessary
to transfer block data between the ARM and the PRUs.

All three major Cameo/Aphid software/firmware components are extensively
commented, so further detail here may be redundant. Good starting places for
reading Cameo/Aphid source code are:

* [profile.py](profile.py): the entire Python program that runs on the ARM.
* [aphd_pru0_datapump.asm](firmware/aphd_pru0_datapump/aphd_pru0_datapump.asm):
  the entire source code for the PRU 0 "data pump" firmware.
* [aphd_pru1_control.cc](firmware/aphd_pru1_control/aphd_pru1_control.cc): core
  of the PRU 1 "control" firmware.

## Future work

Potential future improvements and new features for Cameo/Aphid include:

* 10MB ProFile emulation (easy), or Widget emulation (harder, since many more
  low-level hard drive commands are required).

* Support for Lisa 2/10 drive bay installation: an ongoing effort.

  - :heavy_check_mark:
    Increased robustness to power cuts allow Cameo/Aphid to operate within the
    enclosed drive bay, even though a Lisa powering down can shut down internal
    hard drives without warning.

  - :heavy_check_mark:
    The longer ribbon cable that the 2/10 uses to connect to the Widget in the
    drive bay causes signal quality issues that can lead to malfunctions,
    likely due to ringing or reflections that can confuse the TXS0108E level
    adaptor ICs about signal direction. Inline 100Ω terminating resistors on all
    Cameo signal lines except PEX1, PEX2, and PEX3 appears to dampen the ringing
    well enough for Cameo/Aphid to work.
  
  - :x:
    When Cameo/Aphid and a Lisa 2/10 are powered on at the same time, the Lisa
    boot ROM will attempt to boot from Cameo/Aphid before it is ready, leading
    to a boot error. (Once Cameo/Aphid is ready, the user can then select
    "STARTUP FROM..." to get to the boot menu, then choose to boot from the
    internal drive as usual.) Some other remedy is required before a Lisa 2/10
    can boot from an internally-installed Cameo/Aphid without any user input.

  - :man_shrugging:
    Finally, some substitute for the green hard drive status LED should be
    devised.

* A web browser interface for hard drive image file management: by plugging
  Cameo/Aphid into a modern computer and visiting a designated web address, the
  user can upload and download hard drive image files to an image library, as
  well as select an "active" image that Cameo/Aphid serves to the Apple.
  (Even a relatively small microSD card could easily store several thousand
  hard drive image files.)

* An Aphid-specific level translator PCB design instead of configurable,
  multi-purpose Cameo and its plugboard: it may be possible for the PCB to be
  a two-layer design, offering significant cost advantages. An integral DB-25
  plug connector could be an additional feature.

## Other notes

To the fullest extent possible, Cameo/Aphid is released into the public domain.
Nobody owns Cameo/Aphid.

The modified linker command files for the
[PRU 0](firmware/aphd_pru0_datapump/AM335x_PRU.cmd) and
[PRU 1 firmware](firmware/aphd_pru1_control/AM335x_PRU.cmd) bear copyright
statements by Texas Instruments and are mostly generated automatically by TI's
[Code Composer Studio](http://www.ti.com/tool/CCSTUDIO) IDE.

All other source code files associated with Aphid are forfeited into the public
domain with no warranty. For details, see the [LICENSE](../LICENSE) file.

Apple, ProFile, and Lisa are [Apple Inc.](https://www.apple.com/) trademarks.
PocketBeagle, BeagleBone, and BeagleBone.org are [BeagleBone.org](
http://beaglebone.org) trademarks. Sitara and Code Composer Studio are
[Texas Instruments Inc.](http://www.ti.com) trademarks.

## Acknowledgements

It would not have been possible for me to create Cameo/Aphid without the help
of the following people and resources:

* [Dr. Patrick Schäfer](http://john.ccac.rwth-aachen.de:8000/patrick/index.htm),
  whose [IDEfile](http://john.ccac.rwth-aachen.de:8000/patrick/idefile.htm) and
  [UsbWidEx](http://john.ccac.rwth-aachen.de:8000/patrick/UsbWidEx.htm) project
  pages were invaluable to the project (as were actual UsbWidEx and IDEfile
  devices of my own).
* [bitsavers.org](http://bitsavers.org)'s archived technical documentation.
* The [Sitara Processors Forum](https://e2e.ti.com/support/arm/sitara_arm) on
  the [TI E2E Community](https://e2e.ti.com/).
* Blog posts and other materials by
  [Dr. Andrew Wright](http://theduchy.ualr.edu/), Jason Kridner,
  [Dr. Mark A. Yoder](https://elinux.org/BeagleBoard_Education_Workshops),
  [Ken Shirriff](http://www.righto.com), and others.
* Encyclopedic references like the
  [AM335x Technical Reference Manual](http://www.ti.com/lit/pdf/spruh73), the
  [PRU Assembly Instruction User Guide](http://www.ti.com/lit/pdf/spruij2), the
  [AM335x PRU-ICSS Reference Guide](
  https://elinux.org/images/d/da/Am335xPruReferenceGuide.pdf), the
  [PRU Assembly Language Tools User's Guide](
  http://www.ti.com/litv/pdf/spruhv6b), the
  [PRU Optimizing C/C++ Compiler v2.2 User's Guide](
  http://www.ti.com/litv/pdf/spruhv7b), and the
  [PocketBeagle System Reference Manual](
  https://github.com/beagleboard/pocketbeagle/wiki/System-Reference-Manual).
* Pointers from zmatt of the [`#beagle` IRC channel on irc.freenode.net](
  http://beagleboard.org/chat).
* The entire [LisaList](https://groups.google.com/forum/#!forum/lisalist)
  community.
* Anonymous friends.

## Revision history

11 August 2018: Initial release.
(Tom Stepleton, [stepleton@gmail.com](mailto:stepleton@gmail.com), London)

4 October 2018: Debian 9.5 support, power-cut resilience, boot time,
SD card longevity (Tom Stepleton)
- Debian 9.5 support: adapt to changes to resource table field names and layout.
- Power-cut resilience: introduce a separate FAT32 partition for disk images.
- Power-cut resilience: add overlayfs protection for root filesystem.
- Boot time: disable unused Linux services.
- SD card longevity: only sync disk image changes every four seconds.

20 October 2018: Update to the BeagleBoard.org 2018-10-07 Debian 9.5 image.
(Tom Stepleton)

7 December 2018: Inline 100Ω terminating resistors on signal lines for improved
performance with longer cables. (Tom Stepleton)

6 November 2019: Debian 9.9 support. (Tom Stepleton)

12 January 2020: Upgraded `profile.py` to Python 3.5; the Apple can now command
the emulator to use a different boot image or cease emulation. (Tom Stepleton)

24 January 2021: Many changes, including the "magic blocks" plugin mechanism,
the Selector program, and a bug fix that allows a Lisa to boot reliably from a
Cameo/Aphid attached to the upper port of a 2-port parallel expansion card.
(Tom Stepleton)

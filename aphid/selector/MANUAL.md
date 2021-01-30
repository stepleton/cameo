# Cameo/Aphid Selector

![The Selector running on a Lisa 1](selector.jpg "The Selector in real life")

The Cameo/Aphid drive image selector program ("the Selector" for short) is a
program for Apple Lisa computers that controls a [Cameo/Aphid ProFile hard
drive emulator](https://github.com/stepleton/cameo/tree/master/aphid). Most
Selector users will use the Selector to create, manange, and boot hard drive
images that belong to a catalogue of hard drive images on their Cameo/Aphid
devices.

The Selector is a standalone program, meaning it does not run on top of an
operating system. It can be loaded and run from a hard drive or a floppy drive
(or an emulator of either). When it starts, depending on configuration, it can
present an interactive catalogue of hard drive images (shown above), or it can
automatically select and boot from one of the images.


## Table of contents

* [System requirements](#system-requirements)
* [User interface notes](#user-interface-notes)
  - [A working keyboard is needed for interactive use](#a-working-keyboard-is-needed-for-interactive-use)
  - [Accessibility](#accessibility)
  - [Screensaver](#screensaver)
* [Main interactive interface and menu options](#main-interactive-interface-and-menu-options)
  - [B(oot and S(elect](#boot-and-select)
  - [N(ew](#new)
  - [C(opy](#copy)
  - [R(ename](#rename)
  - [D(elete](#delete)
  - [A(utoboot toggle](#autoboot-toggle)
  - [M(oniker](#moniker)
  - [K(ey/value](#keyvalue)
  - [P(ort](#port)
  - [Q(uit](#quit)
* [Autobooting](#autobooting)
* [Scripting](#scripting)
* [Potential improvements](#potential-improvements)
* [Acknowledgements](#acknowledgements)
* [Revision history](#revision-history)


## System requirements

The Selector is designed to run on any Apple Lisa computer, but a Cameo/Aphid
hard drive emulator (or a compatible device) must be connected to one of its
parallel ports in order for it to do anything useful. The emulator may be
connected to any parallel port, including ports on 2-port parallel expansion
cards. The Selector will not work on computers with Macintosh XL screen
modifications, nor on computers with most other modifications that would make
it impossible for the computer to run the Lisa Office System.

The Selector only works with Cameo/Aphid hard drive emulators running the
Cameo/Aphid software current to February 2021 or later.

Emulator designers who are interested in making Selector-compatible ProFile
emulators can find details of how the Selector controls the Cameo/Aphid in [the
Protocol document](PROTOCOL.md).


## User interface notes

### A working keyboard is needed for interactive use

The Selector uses a text-based user interface, and you control the Selector
entirely with the keyboard. A working keyboard is therefore necessary to use
the Selector in an interactive way. The Selector does not require a working
keyboard if it is configured to select and boot from one of the hard drive
images automatically, as this process does not require any user input.

### Accessibility

The Selector has poor accessibility for people with certain kinds of visual
impairments. Other shortcomings may exist.

If you are having trouble using the Selector due to any of its accessibility
limitations, please [contact me via email](mailto:stepleton@gmail.com).

### Screensaver

The Selector has a built-in screensaver that displays a scrolling texture on
the screen. At certain places where the Selector expecting user input, it will
automatically start the screensaver after around 90 seconds of waiting. You can
exit the screensaver by pressing any key.

![The Selector's screensaver starting up](screensaver.jpg
"The Selector's screensaver starting up")

The Selector is not capable of activating the screensaver in all situations
where it expects user input --- for example, input textboxes like those used to
collect filenames cannot be interrupted by the screensaver. It's hoped that the
screensaver works now in most of the situations where the Selector is likely to
be left unattended. Don't rely on the Selector's screensaver alone to protect
your Lisa's CRT from burn-in.

The screensaver's scrolling texture is based on the [Rule 30](
https://en.wikipedia.org/wiki/Rule_30) elementary finite automaton, which was
discovered around the time the Lisa was developed. It expands from a single
pixel and widens to stretch across the entire screen.


## Main interactive interface and menu options

The main interactive interface for the Selector presents a screen that looks
like this:

```

 [No Name] Command: B(oot, S(elect, N(ew, C(opy, R(ename, D(elete, ? [0.7]

  Filename                                                    1,234,567,890 bytes free
 --------------------------------------------------------------------------------------
  Hard_drive_image_01.image
  Hard_drive_image_02.image
  Hard_drive_image_03.image
  Hard_drive_images_can_have_arbitrary_names.image
  Hence_these_filenames_are_just_examples.image
  profile.image






















 --------------------------------------------------------------------------------------
  Cameo/Aphid up 1d 23:34:45, load average 0.43, 0.32, 0.21, processes 67:1

```

A catalogue of drive image files present on the Cameo/Aphid occupies most of
the screen. Within the catalogue, one of the image files will be selected at
all times, with its filename highlighted in inverse video. You can change the
selection by using the arrow keys (`[▲]` or `[▼]`) or the 8 and 2 keys on the
keypad to move the selection up and down respectively.

The top of the screen shows a partial menu of keyboard commands:
```
 [No Name] Command: B(oot, S(elect, N(ew, C(opy, R(ename, D(elete, ? [0.7]
```
The bracket `(` indicates that the first letter of the command activates the
command, thus the `C` key will start the Copy command. Also shown here are the
version number of the Selector software (the `0.7` in square brackets at right)
and the "moniker" for this Cameo/Aphid (the `No Name` in square brackets at
left). A moniker is a name given to a Cameo/Aphid for identification purposes:
more precisely, it's a name given to a microSD card containing an installation
of the Cameo/Aphid system software, since microSD cards can be moved between
Cameo/Aphid devices, and all the configuration and hard drive image files on
the cards will move with them.

Typing a `?` will change this top line to show an additional menu of keyboard
commands:
```
 [No Name] Command: A(utoboot toggle, M(oniker, K(ey/value, P(ort, Q(uit
```
Typing `?` toggles between displaying both partial menus, so typing it again
here will result in the display of the first menu. Although only some of the
keyboard commands are shown on the screen at any moment, all commands are
available in the main interface regardless of what can be seen; even if the menu
just above is displayed, you can still use the `C` key to execute the Copy
command.

Beneath the menu and above the catalogue, on the right side of the screen, the
free space remaining for drive images on the Cameo/Aphid appears. It is shown as
`1,234,567,890 bytes free` in the screen depiction above. (Available space may
be much smaller than the size of your microSD card, since it depends on how much
of your card has been reserved for storing hard drive images. For [default
installations of the Cameo/Aphid system software](
https://github.com/stepleton/cameo/tree/master/aphid#software-installation),
this amounts to around 500 MiB, still enough room for lots of ProFile hard drive
images.)

Basic runtime information about the Cameo/Aphid system appears beneath the
catalogue. This information resembles the information printed by the [`uptime`
command](https://man7.org/linux/man-pages/man1/uptime.1.html) on Unix-like
operating systems, except it shows the number of running and total processes
instead of the number of logged-in users. This information updates around once
every two seconds. It serves little purpose except to look "geeky" and to
demonstrate that the Cameo/Aphid is operating and responsive.

The rest of this section describes all of the keyboard commands.

### B(oot and S(elect

The **Select** command causes the Cameo/Aphid to switch its current hard drive
image to the one selected in the catalogue display. The **Boot** command does
the same, then attempts to boot the Lisa from that hard drive image.

When the Cameo/Aphid switches to a different hard drive image, this means that
all reads and writes to the emulated hard drive will access data from the
new hard drive image instead of the image the Cameo/Aphid was serving
previously.

On most Cameo/Aphid installations, a hard drive image change will persist until
the Selector changes the image again or until the Cameo/Aphid is restarted.
Rebooting or turning off the Lisa has no effect on the Cameo/Aphid --- it merely
appears to the emulator that the computer has stopped sending commands for a
little while --- so if you wish to return to the Selector, it's typically
necessary to shut down and restart the Cameo/Aphid itself or to boot the
Selector from a floppy disk.

### N(ew

The **New** command is for creating new ProFile hard drive images. It presents
this interface:
```

 { New image }

 New filename: [Untitled.image                                                         ]

 Return (↵) to proceed, Clear (⌧) to cancel.

```
You can modify the new filename with the keyboard in a conventional way, but the
`.image` suffix cannot be changed. After you press Return, the Selector will
check to make sure that the filename isn't already in use by another image file,
then issue an image file creation command to the Cameo/Aphid.

Even if these steps complete successfully, the Cameo/Aphid may refuse to
generate the new drive image for one reason or another: perhaps the name you've
specified contains illegal characters like '/', or maybe there's not enough
empty space left to hold a new hard drive image. Browse the drive image
catalogue to be certain that your new hard drive image has been created.

### C(opy

The **Copy** command is for duplicating ProFile hard drive images. It presents
this interface:
```

 { Copy image }

    Copy from:  Xenix_3.0_rel1.image
 New filename: [Xenix_3.0_rel1.image                                                   ]

 Return (↵) to proceed, Clear (⌧) to cancel.

```
The "Copy from:" filename was the highlighted catalogue filename when the Copy
command was executed at the main interface by pressing the `C` key.

You can modify the filename for the duplicate image in a conventional way, but
the `.image` suffix cannot be changed. You must specify a novel filename in
order for the duplication to work, so some modification is required. After you
press Return, the Selector will check to make sure that the filename isn't
already in use by another image file, then issue a duplication command to the
Cameo/Aphid.

Even if these steps complete successfully, the Cameo/Aphid may refuse to
generate a duplicate drive image for one reason or another: perhaps the name
you've specified contains illegal characters like '/', or maybe there's not
enough empty space left to hold a new hard drive image. Browse the drive image
catalogue to be certain that the duplicate hard drive image has been created.

### R(ename

The **Rename** command is for duplicating ProFile hard drive images. It presents
this interface:
```

 { Rename image }

 Old filename:  GEMDOS_Experimental.image
 New filename: [GEMDOS_Experimental.image                                              ]

 Return (↵) to proceed, Clear (⌧) to cancel.

```
The "Old filename:" was the highlighted catalogue filename when the Rename
command was executed at the main interface by pressing the `R` key.

You can modify the new filename for the image in a conventional way, but the
`.image` suffix cannot be changed. You must specify a novel filename in order
for the renaming to work, so some modification is required. After you press
Return, the Selector will check to make sure that the filename isn't already in
use by another image file, then issue a renaming command to the Cameo/Aphid.

Even if these steps complete successfully, the Cameo/Aphid may refuse to rename
the drive image for one reason or another: perhaps the name you've specified
contains illegal characters like '/'. Browse the drive image catalogue to be
certain that the hard drive image has been renamed.

The Cameo/Aphid will not rename the drive image file called `profile.image`,
since this is the drive image that the emulator uses by default when it is
powered on. Usually this drive image contains the Selector itself.

### D(elete

The **Delete** command is for deleting ProFile hard drive images. It presents
this interface:
```

 { Delete image }

   Image file: MacWorks_Plus.image

 This operation CANNOT BE UNDONE!
 Return (↵) to proceed, Clear (⌧) to cancel.

```
The "Image file:" filename was the highlighted catalogue filename when the
Delete command was executed at the main interface by pressing the `D` key.

After you press Return, the Selector will check to make sure that the filename
is present in the catalogue (it's unlikely that this will fail), then issue a
deletion command to the Cameo/Aphid.

Even if these steps complete successfully, the Cameo/Aphid may refuse to
delete the drive image for one reason or another: for example, it won't delete
the image file called `profile.image`, since this is the drive image that the
emulator used by default when it is powered on. (Usually this drive image
contains the Selector itself.) Browse the drive image catalogue to be certain
that the hard drive image has been deleted.

### A(utoboot toggle

The **Autoboot toggle** command lets you enable, disable, or configure the
Selector's ability to "autoboot" from one of the disk images, which means
that shortly after the Selector is first started, it will carry out the
operations of the **Boot** command on that disk image without any input from
the user. See the [Autobooting](#autobooting) section for more details.

If autoboot is disabled, the `A` key will result in this interface:
```

 { Autoboot setup }

   Pascal_Workshop_3.9.image

 S)et autoboot to this file, or C)ancel?

```
If autoboot is already enabled, the list of options is
```
 T)urn off autoboot, S)et autoboot to this file, or C)ancel?
```
Either way, the displayed filename was the highlighted catalogue filename when
the Autoboot toggle command was executed at the main interface.

Typing `T` here will disable autoboot, which means that on boot, the Selector
will present the main interactive interface. Typing `S` will enable autoboot for
the drive image file shown.

### M(oniker

The **Moniker** command lets you change the "moniker" associated with the
microSD card in your Cameo/Aphid (and therefore with the collection of drive
image files and the Selector configuration on that microSD card). A moniker is
a name used for identification purposes, and it may be useful if you have
multiple Cameo/Aphid devices or use more than one microSD card in your
Cameo/Aphid. The moniker may also be useful for advanced scripts (see the
[Scripting](#scripting) section for details).

The Moniker command presents this interface:
```

 { Change moniker }

 Moniker: [No Name        ]

 Return (↵) to proceed, Clear (⌧) to cancel.

```
A moniker may be up to 15 characters long. It cannot be empty.

### K(ey/value

The **Key/value** command is a "power user" command that allows you to edit
entries in the Cameo/Aphid's durable key/value store. The [description of the
key/value store in the protocol description document](
PROTOCOL.md#block-fffeff-durable-keyvalue-store) clarifies the meanings of
the fields in the Key/value command's interface:
```

 { Key/value store editor }

       Key: [Some arbitrary key  ]
 Cache key: [Sk]

 Edit which row (1-8), W(rite to the key/value store, or C(ancel?

 1: 000-03F [Here are the 512 bytes of data that are associated with the key ]
 2: 040-07F ["Some arbitrary key  " in the Cameo/Aphid key/value store. The d]
 3: 080-0BF [ark rectangles represent $00 bytes.█████████████████████████████]
 4: 0C0-0FF [████████████████████████████████████████████████████████████████]
 5: 100-13F [████████████████████████████████████████████████████████████████]
 6: 140-17F [████████████████████████████████████████████████████████████████]
 7: 180-1BF [████████████████████████████████████████████████████████████████]
 8: 1C0-1FF [████████████████████████████████████████████████████████████████]

```
The editor requests the key and cache key for the entry you wish to edit
before it reads and presents the value data for the entry in the rows numbered
1 through 8. Editing capabilities are rudimentary, with each row allowing you
to modify 64-byte segments of the value data in a conventional way.

When you use the `W` key to tell the Selector to update the key/value store
entry, the Selector first asks if it should replace the final two bytes of the
value data with a computed checksum word:
```
 Replace bytes 1FE-1FF with a checksum before writing? (Y/N)
```
The Selector keeps configuration information under certain keys in the key/value
store. Most of this information must be accompanied by a valid checksum word in
order for the Selector to consider the data valid.

### P(ort

The **Port** command changes the parallel port in use by the Selector. By
changing parallel ports, you can use the Selector to control multiple
Cameo/Aphid devices connected to the same computer. This command presents this
interface:
```

 { Choose parallel port }

 Scanning for connected Cameo/Aphid devices... done.
 (1) Built-in parallel port: "My Moniker"
 (4) Lower port on expansion slot 2: "Other Moniker"
 (5) Upper port on expansion slot 2: "Moniker #3"

 Please select a parallel port by number.

```
As it prepares this menu, the Selector program scans all of the Lisa's parallel
ports. When it finds a port with a Cameo/Aphid device attached, it displays the
port as a menu item along with the Cameo/Aphid's moniker. The numbers that
select different parallel ports are not always contiguous because menu items
for ports without Cameo/Aphid devices connected to them are not shown.

Selecting a parallel port from the menu will return you to the main interactive
interface, with the drive image catalogue showing drive image files on the
Cameo/Aphid device connected to that port.

The Selector automatically executes the Port command immediately after start-up
if it is loaded from a device that isn't a Cameo/Aphid. The appearance of its
on-screen display has cosmetic differences to the example shown above in this
situation.

### Q(uit

The **Quit** command causes the Selector program to terminate and return control
of the computer to the Apple Lisa boot ROM.


## Autobooting

The Selector's "autoboot" mechanism allows the Selector to automatically switch
the hard drive image that the Cameo/Aphid is serving to the Lisa and then boot
from that hard drive image. This mechanism enables a style of working with the
Cameo/Aphid that resembles the use of an ordinary hard drive (turn on the
drive, turn on the Lisa, then boot from the hard drive without intervention)
whilst still allowing you to interrupt the process and use the Selector if you
choose.

With autoboot enabled, the Selector prints information like the following to the
screen prior to booting from the designated hard drive image:
```

 [Cameo/Aphid]
 Hard drive image manager v0.7
 Connecting to the boot drive: the built-in parallel port... OK
 Loading configuration into the key/value cache... OK
 Reading configuration... OK
 Reading key/value data from cache... OK

 (Any key to interrupt) Running autoboot program in 3...2...1...

 Updating the drive image catalogue... OK
 Checking that there is a drive image called blu.image... OK
 Changing the drive image to blu.image... OK
 Booting from the built-in parallel port...

```
Most status messages shown are not very important when everything is working,
but they may help you troubleshoot if something goes wrong. Otherwise, the most
important item is the `3...2...1...` countdown, which takes several seconds to
complete. During that time, you may interrupt the autoboot process by pressing
any key, which takes you to the main interactive interface.

The autoboot mechanism is built on the Selector's rudimentary [scripting
capability](#scripting) and may be coerced into doing more sophisticated things
than booting a single hard drive image.

See the [Autoboot toggle](#autoboot-toggle) command description for information
on enabling and disabling autobooting.


## Scripting

The [autoboot mechanism](#autobooting) uses a rudimentary scripting capability
built into the Selector. When autobooting is enabled, a small script is written
to the key/value store that tells the Selector to perform all of the steps of
the autoboot process. For a hard drive image called `kazoo.image`, the script
would look like this:
```
ClogImag0Akazoo.image_BootHalt
```
This script contains four commands: `Clog`, which means "update the drive image
catalogue"; `Imag`, meaning "switch to the following hard drive image"; `Boot`,
"boot from the hard drive image"; and `Halt`, marking the end of the script.
The terse "scripting language" is designed more for the Selector's convenience
than the user's, but it is at least possible to use the [key/value editor](
#keyvalue) to make more elaborate custom scripts.

Scripts are made of sequences of commands and their arguments. There is no
flow control, and any command that fails will cause the script to terminate.
All commands have four-byte names and must be "word-aligned" within the script:
that is, they must be positioned so that they begin on even-numbered bytes. This
explains the `_` character inside the example above: it's meaningless padding
between the end of the "kazoo.image" argument value and the `Boot` command.

Except for padding bytes, there is no spacing between script commands.

Here is a list of the commands that you can use in scripts. **Note that only
the `Clog`, `Imag`, `Boot`, and `Halt` commands have been tested at time of
writing.**

* `Halt`: Immediately terminate the script. The Selector will interpret any
  script that reaches a `Halt` command as having completed successfully.

* `Scan`: Scan all parallel ports on the computer for attached Cameo/Aphid
  devices and update the drive catalogue. If you intend to use the `Name`
  command in an autoboot script, it will be necessary to execute this command
  first, since the Selector does not automatically scan for Cameo/Aphid devices
  when it first runs.

* `Name`: followed by a 2-digit hexadecimal number (e.g. `0C` for 12) and then
  a string argument of that many characters _plus one_ (e.g. `ThirteenChars`).
  If the string argument has an odd number of characters, you must follow it
  with a meaningless padding byte, e.g. `^`. (Complete example:
  `ThirteenChars^`)

  Search the drive image catalogue for a Cameo/Aphid device whose moniker is the
  same as the string argument, which means the drive image catalogue must be
  up-to-date (see the `Scan` command). If one is found, make that device's
  parallel port the Selector's current parallel port.

* `Home`: Make the parallel port hosting the Cameo/Aphid that was used for
  booting the Lisa the current parallel port. Will fail if the boot device was
  not a Cameo/Aphid (for example, if it was a floppy disk).

* `Boot`: Boot the Lisa from the hard drive device on the Selector's current
  parallel port. If the hard drive device is a Cameo/Aphid, then whatever drive
  image is the current drive image on that device will be the drive image that
  the Cameo/Aphid serves during and after the boot process.

* `Clog`: Refresh the drive image catalogue. If you intend to use the `Imag`
  command in an autoboot script or after changing the current parallel port
  (via `Home` or `Name`), it will be necessary to execute this command first,
  since the `Imag` command will check to see whether a drive image file exists,
  and the Selector does not update the drive image catalogue automatically when
  it first runs or when it switches parallel ports.

* `Imag`: followed by a 2-digit hexadecimal number (e.g. `1A` for 26) and then
  a string argument of that many characters _plus one_ (e.g.
  `Workshop_(Pascal)_3.9.image`). If the string argument has an odd number of
  characters, you must follow it with a meaningless padding byte, e.g. `~`.
  (Complete example: `Imag1AWorkshop_(Pascal)_3.9.image~`)

  Tell the Cameo/Aphid device on the current parallel port to switch the current
  hard drive image to the specified file. Fails if the specified image doesn't
  exist in the catalogue, which means the catalogue must be up-to-date (see the
  `Clog` command). Use the `Ima!` command if you'd like to skip the catalogue
  check.

* `Ima!`: Same as the `Imag` command, except it doesn't check whether the
  specified drive image exists in the drive image catalogue.

* `Prnt`: followed by a 2-digit hexadecimal number (e.g. `0B` for 11) and then
  a string argument of that many characters _plus one_ (e.g. `Hello world!`).
  If the string argument has an odd number of characters, you must follow it
  with a meaningless padding byte, e.g. `+`. (Complete example:
  `Prnt0CHello Planet!+`)

  Print a string to the display. Does not print additional newlines or any other
  characters besides what you specify.

* `Read`: followed by the characters `01` and then a two-byte cache key (e.g.
  `Hi`).

  (This is an advanced command that requires a good understanding of the
  [key/value store](PROTOCOL.md#block-fffeff-durable-keyvalue-store) and, if
  used in scripts alongside the `Name` or `Home` commands, some caution about
  which Cameo/Aphid the Selector is communicating with.)

  Read a script from the cache of the key/value store in the Cameo/Aphid device
  on the current parallel port, then run it. Scripts are up to 510 bytes long
  (you don't have to use all that space) followed by a two-byte checksum word
  (see the [key/value editor](#keyvalue) editor documentation for more
  information about checksums).

  In order for the `Read` command to read a script by its two-byte cache key,
  the script must already be resident in the cache of the Cameo/Aphid's
  key/value store. Any Cameo/Aphid device that has been detected by the `Scan`
  command is guaranteed to have loaded these key/value store entries into the
  cache:

  - `Selector: script 00 ` (note trailing space) under cache key `Sa`. This is
    the script that the Selector will run on start-up if autobooting is enabled.
  - `Selector: script 01 ` (note trailing space) under cache key `Sb`.
  - `Selector: script 02 ` (note trailing space) under cache key `Sc`.
  - `Selector: script 03 ` (note trailing space) under cache key `Sd`.
  - And so on for `03` through `21` and cache keys `Se` through `Sv`
    respectively, giving 22 scripts accessible to the `Read` command on any
    Cameo/Aphid device.

A more elaborate autoboot script could use several of these commands to prepare
a Lisa with three Cameo/Aphid devices to host a "large scale" Xenix
installation with three ProFile hard drives. Imagine that the Cameo/Aphid
connected to the built-in parallel port is called "Alice", and that two more
Cameo/Aphid devices with the names "Bob" and "Carol" are connected to the
parallel ports on a 2-port parallel expansion card. This script
```
Scan
Name02Bob~ClogImag0EXenix_Usr.image~
Name04Carol~ClogImag13Xenix_UsrLocal.image
Name04Alice~ClogImag0FXenix_Root.image
BootHalt
```
(where line breaks have been added for display purposes only) tells Bob, Carol,
and Alice to switch to the drive images `Xenix_Usr.image`,
`Xenix_UsrLocal.image`, and `Xenix_Root.image` respectively, then tells Alice
to boot the Lisa from `Xenix_Root.image`. Note placement of padding bytes where
necessary, use of the `Clog` command prior to `Imag`, and the final `Halt`
command for consistency's sake, even though the `Boot` command is unlikely to
ever finish running (instead, presumably, it will boot the Xenix operating
system, which will evict the Selector from memory altogether).

Most script commands print information to the display, allowing you to monitor
their progress (if you can read fast enough) and to know where an error has
occurred if trouble is encountered.


## Potential improvements

#### 1. Pressing the power button should shut down the Lisa

At present, the Selector ignores the power button. A full-featured Lisa
shutdown should eject diskettes from floppy drives and dim the display before
turning off the Lisa.

#### 2. The Selector should eject its boot disk if it is booted from a floppy

A floppy disk that boots the Selector will not be readable to common Lisa
operating systems, and if it remains in the disk drive after one of those
operating systems boots, it may be possible to format the disk by accident.

#### 3. It should be possible to copy drive images between two Cameo/Aphids

#### 4. It should be possible to transfer drive images over the serial port

It's possible that the best place for both of these features is a separate
computer program. When the Selector boots, the entire Selector program is
loaded into memory, and bundling in more features mean longer load times.

#### 5. There should be a way to password-protect the interactive interface

In public settings, an observer watching the "countdown delay" part of the
autoboot process may be tempted to interrupt the autoboot and peruse the drive
image catalogue. While it would offer little practical security, a password
challenge prior to entering the main interactive interface could e.g. help
prevent computer museum guests from disabling interactive exhibits, whether on
purpose or by accident.

#### 6. There should be a way to run scripts besides the autoboot mechanism

At present, the only way to run a custom script is to enable the autoboot
mechanism and then manually edit the autoboot script in the key/value editor.
Custom scripts may be useful for purposes besides autobooting, and it may be
useful to be able to invoke a custom script manually.

#### 7. The Selector should be able to install itself onto boot media

[The BLU program](http://sigmasevensystems.com/BLU.html) can install itself
onto hard drives and floppy disks. It may not be so difficult for the Selector
to do something similar.


## Acknowledgements

It would not have been possible for me to create the Cameo/Aphid hard drive
image selector without the help of the following people and resources:

- [Dr. Patrick Schäfer](http://john.ccac.rwth-aachen.de:8000/patrick/index.htm),
  whose [UsbWidEx](http://john.ccac.rwth-aachen.de:8000/patrick/UsbWidEx.htm)
  device was invaluable to early development of the Cameo/Aphid plugin system.
- [bitsavers.org](http://bitsavers.org)'s archived technical documentation.
- The [EASy68K-asm](https://github.com/rayarachelian/EASy68K-asm) standalone
  assembler 
- The [LisaEm](http://lisa.sunder.net) emulator by Ray Arachelian.
- The [Floppy Emu](http://www.bigmessowires.com/floppy-emu/) floppy drive
  emulator.
- The [BLU](http://sigmasevensystems.com/BLU.html) utility by James MacPhail
  and Ray Arachelian.
- The entire [LisaList2](https://lisalist2.com/) community.


## Revision history

17 January 2021: Initial release.
(Tom Stepleton, [stepleton@gmail.com](mailto:stepleton@gmail.com), London)

24 January 2021: 0.6 release, adding the S(elect command. (Tom Stepleton)

30 January 2021: 0.7 release, adding a screensaver. (Tom Stepleton)

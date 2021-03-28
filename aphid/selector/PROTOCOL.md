# "Magic blocks" used by the Cameo/Aphid drive image selector

The Cameo/Aphid drive image selector program ("the Selector" for short) is a
computer program for the Apple Lisa that allows you to create, manage, and boot
from ProFile drive image files on a Cameo/Aphid ProFile hard drive emulator.
Behind the scenes, the Selector accomplishes this by sending specially
formatted read and write commands to the drive emulator that target unusual
hard drive blocks.

The Selector is not the only program that can use these "magic blocks", and any
hard drive emulator that understands these special reads and writes will be
compatible with the Selector. This document describes the format of these reads
and writes for the benefit of anyone who wishes to take advantage of this
capability.

This document was created as part of the Cameo/Aphid hard drive emulator
project at [https://github.com/stepleton/cameo/tree/master/aphid].

## Block `FFFFFF`: "Magic block" capability identification

The Selector reads from block `FFFFFF` to identify whether the connected drive
is a ProFile emulator that supports the "magic block" protocol described here.
If bytes $20-$2B of the returned block are `Cameo/Aphid ` and bytes $2C-$2F are
a 32-bit integer greater than or equal to $30303031 (i.e. `0001`), then the
Selector may assume that it is talking to a compatible emulator.

Note that ordinary ProFile hard drives respond to reads on block `FFFFFF` with
"artificial" block data that contains information about the hard drive. Drives
with ROM version $0398 that allocate no bad blocks or spare blocks only need
bytes $00-$1F to encode this information, so the adjacent bytes occupied by the
"magic block" capability identifier will not interfere with it.

## Block `FFFFFD`: "Built-in" emulator commands

Writes to block `FFFFFD` with write count and sparing threshold parameters `FE`
and `AF` respectively will issue "built-in" commands to the hard drive
emulator. These commands are encoded in the block data written to the drive.
("Built-in" refers to an implementation detail of the Cameo/Aphid emulator and
is not important to this description.) There are currently two "built-in"
commands:

1. If bytes $00-$03 of the block data are `HALT`, the emulator will immediately
   shut down after completing any uncommitted writes to the currently open
   hard drive image file.

2. If bytes $00-$06 of the block data are `IMAGE:`, then subsequent bytes
   should be a null-terminated string specifying the name of a hard drive image
   file. If this filename corresponds to an actual file, the emulator will flush
   any uncommitted writes to the hard drive image file currently in use, then
   then immediately close that file and open the specified hard drive image
   file in its place. The program issuing this command should give the
   emulator adequate time to switch between hard drive image files.

Neither command provides any response or any other overt indication of success
or failure; programs should attempt to deduce the outcome in other ways.

(Note: the [IDEfile emulator](
http://john.ccac.rwth-aachen.de:8000/patrick/idefile.htm) uses a similar but
distinct "magic block" mechanism on block FFFFFD for access to its volume
table.)

## Block `FFFEFF`: Durable key/value store

Reads and writes to block `FFFEFF` provide access to a durable (i.e. retained
through reboots of the hard drive emulator) key/value store. Keys are 20 bytes
long; values are 512 bytes long. This store remains accessible no matter which
disk image file is currently in use by the emulator.

The facility presents as having a kind of volatile (that is, not retained
through system reboots) write-through cache where the 65,535 cache entries are
software controllable (as opposed to being controlled automatically, as with a
CPU cache for example). Cache keys are 16-bit values formed by the
concatenation of the retry count and the sparing threshold specified during a
ProFile read or a write. Reads can only request items from the cache, so
earlier writes must have directed the store to have loaded data there from the
durable key/value store. For writes, software must specify both a cache key and
the 20-byte store key; the data will be saved in both the cache and the durable
store automatically.

Operations:

- ProFile reads to `FFFEFF`: Retrieve the cache entry assocated with the 16-bit
  concatenation of the retry count and sparing threshold parameters specified
  in the read. The store key will be the first 20 bytes of the returned data;
  the value is the remaining 512 bytes.

- ProFile writes to `FFFEFF` with retry count and sparing threshold both set to
  $FF: Order the store to load key/value pairs into the cache. The data in the
  write has the following format:

      Byte      0: Number of key/value pairs to load (up to 24)

      Bytes   1-2: 2-byte key for the cache entry receiving the first value
      Bytes  3-22: 20-byte key of the value to load into that cache entry

      Bytes 23-24: 2-byte key for the cache entry receiving the second value
      Bytes 25-44: 20-byte key of the value to load into that cache entry

  And so on.

- ProFile writes to `FFFEFF` with any other retry count and sparing threshold
  parameters: Write data to the cache entry specified by the parameters and to
  the key/value store. The store key is the first 20 bytes of the data, and the
  value is the remaining 512 bytes.

From a logical perspective, any store keys not yet associated with any data are
paired with 512 $00 bytes, and any cache keys not yet associated with any data
are associated with 532 $00 bytes (in other words, an all-$00 20-byte key and
512 bytes of all-$00 data).

## Block `FFFEFE`: Filesystem operations

Reads and writes to this block enable some basic filesystem operations.  For
safety, operations may be limited to files with a particular suffix.

Operations:

- ProFile reads to `FFFEFE`: Retrieve information about a file in the current
  working directory. The emulator maintains a list of files (usually limited
  to those with a specific suffix, like ".image"), and a read obtains
  information about the n'th file in the list, where n is the 16-bit
  concatenation of the read's retry count and sparing threshold parameters.
  The contents of the 532-byte reply are:

      Bytes    0-3: Nonce
      Bytes    4-5: Number of files in the directory (suffix-limited)

      Bytes   6-19: YYYYMMDDHHMMSS ASCII last-modified time for the file
      Bytes  20-29: 10-character ASCII right-justified space-padded file size
      Bytes 30-275: Reserved, unused for now
      Bytes 276-??: Filename (length varies---up to 255 characters long)

         Remainder: $00 bytes, so the filename is null-terminated.
                    (There is always room for at least one null terminator.)

  By counting through values of n in the ProFile read parameters, programs
  that talk to the emulator can download a complete directory listing to
  present to the user. Programs that do this should save the nonce value at the
  beginning of one of the replies, which will change if and only if the contents
  of the current working directory change: as long as the nonce stays the same,
  the program will not need to download a new directory listing.

  (This strategy will not notice changes to file metadata like last-modified
  times or file sizes; the program will need to download a complete listing
  again if it's important to keep that data up-to-date.)

  If the program specifies an n greater than or equal to the number of
  (suffix-limited) files in the directory, the reply will list an empty 0-byte
  file with a length-0 filename.

- ProFile writes to `FFFEFE`: Order the Cameo/Aphid to perform a filesystem
  operation in the current working directory, or change some aspect of the
  behaviour of the "magic block". Here, the 16-bit concatenation of the write's
  retry count and sparing threshold parameters direct which operation to
  perform, and the data contents are the parameters. Excess space in the
  parameter data may be padded arbitrarily.

  For readability, the 16-bit command is usually made of ASCII characters.
  Commands are:

  - 'cp': copy a file. Parameters are a null-terminated source filename and a
    null-terminated destination filename immediately following. There must be
    no existing file at the destination.

  - 'mv': move a file. Parameters are a null-terminated source filename and a
    null-terminated destination filename immediately following. There must be
    no existing file at the destination.

  - 'mk': create a new disk image. The only parameter is a null-terminated
    filename for the new image. There must be no existing file by that name.

  - 'mx': create a new disk image, extended. Parameters are a null-terminated
    numeric size string and a null-terminated filename for the new image
    immediately following. There must be no existing file by that name.

  - 'rm': remove a file. The only parameter is the null-terminated name of
    the file to remove.

  - 'sx': set the file suffix to the one null-terminated parameter. The
    emulator will only list or operate on files that end with this suffix. (For
    file extensions like '.image', you must include the '.' character.) It is
    valid to specify an empty suffix.

  The emulator may refuse to carry out any of these operations for any reason.
  Furthermore, no feedback is returned about whethere an operation has been
  successful. For any operation that modifies the filesystem, one workaround
  is to perform a read and see whether the nonce has changed.

Filenames are sent to and from the emulator in the ISO-8859-1 (Latin-1)
character encoding.

## Block `FFFEFD`: Emulator status

Reads of this block retrieve basic system status information from the emulator.
The format in use is a good fit for emulators that incorporate Unix-like
operating systems (like Cameo/Aphid does) but may not be as useful for other 
implementations.

   Bytes   0-9: DDDDHHMMSS ASCII uptime; days right-justified space padded
   Bytes 10-24: ASCII right-aligned space-padded filesystem bytes free
   Bytes 25-31: ASCII null-terminated 1-minute load average
   Bytes 32-38: ASCII null-terminated 5-minute load average
   Bytes 39-45: ASCII null-terminated 15-minute load average
   Bytes 46-50: ASCII null-terminated number of processes running
   Bytes 51-55: ASCII null-terminated number of total processes

## Block `FFFEFC`: Selector rescue

This block provides read-only access to disk images of the Selector program
that are kept separate from hard drive image data stored on a Cameo/Aphid hard
drive emulator. It is impossible for any Apple connected to a Cameo/Aphid
device to alter or damage these disk images. Additionally, one particular read
to this block will

Operations:

- ProFile reads to $FFFEFC: have effects that depend on the 16-bit concatenation
  of the read's retry count and sparing threshold parameters. These are:

  - $FFFF: copy the contents of a ProFile drive image containing the Selector
    program to `profile.image` in the current working directory, then trigger
    the start of a new emulation session using `profile.image` as the current
    hard drive image. If a file called `profile.image` already exists, it will
    be renamed to `profile.backup-X.image`, where `X` is the first number
    counting up from 0 that yields an unused filename. The block contents
    retrieved by this read are unspecified.

  - $0XXX: retrieve the $XXXth 532-byte block of a ProFile drive image
    containing the Selector program, in a format suitable for use with a
    Cameo/Aphid device; or, if the drive image is less than ($XXX - 1) * 532
    bytes long, retrieve a block of 532 $00 bytes.

  - $1XXX: retrieve the $XXXth 532-byte block of a DC42-format 400K disk image
    containing the Selector program, suitable for installation on a 400K 3.5"
    diskette or for use with the Floppy Emu floppy drive emulator; or, if the
    disk image is less than ($XXX - 1) * 532 bytes long, retrieve a block of
    532 $00 bytes.

  - $2XXX: retrieve the $XXXth 532-byte block of a DC42-format Twiggy disk image
    containing the Selector program, suitable for installation on a Twiggy
    diskette; or, if the disk image is less than ($XXX - 1) * 532 bytes long,
    retrieve a block of 532 $00 bytes.

- ProFile writes to $FFFEFC: do nothing at all.


-- _[Tom Stepleton](mailto:stepleton@gmail.com), 28 March 2021, London_

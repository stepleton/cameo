#!/usr/bin/python3
"""Apple parallel port storage emulator for Cameo

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

When run atop the entire Cameo cape/Aphid PRU firmware stack, emulates a
ProFile hard drive. Backing storage is a single file (a "disk image file")
mmap'd into this program's process space. For accurate simulation of an
ordinary 5 MB ProFile, the disk image file should be 5,175,296 bytes in size,
for a ProFile-10, 10,350,592 bytes. Any other drive image announces itself to
the Apple as a 5 MB ProFile with a strange number of available blocks, a
convention intended to replicate the behaviour of X/ProFile.

Run with the --help flag for usage information.

Includes a plugin system that allows some blocks to be "magical". See the
file header comment in `profile_plugins.py` for details.

Most installations of the emulator will run in "headless" mode (i.e. without
any console for displaying log messages), so this program displays some basic
status information on the user LEDs. Light patterns and their meanings include:

* All four LEDs on "solid": the emulator is ready to serve requests from
  the Apple. (When it does, the LEDs will blink off momentarily, much like
  the "READY" LED on a real drive.) While in this mode, the emulator may lose
  data if it is shut down unexpectedly.

* Rapid "cycling" pattern: the emulator is either initialising or awaiting
  system shutdown; either way, to the fullest extent that this program can
  guarantee it, all data should be written to the storage device.

* The two centre LEDs blink slowly in unison: the emulator has encountered an
  unrecoverable error and is busy doing nothing. All attempts have been made to
  preserve the disk image data. Try restarting the PocketBeagle. 

Any other light pattern that persists at length is either an indication that
the emulator is not running or that some other, unforeseen error has occurred.
"""

import argparse
import contextlib
import logging
import mmap
import os
import select
import signal
import struct
import sys
import threading
import time

from typing import BinaryIO, Dict, Generator, Iterator, Optional, Tuple, NamedTuple

import profile_plugins


###################
#### Constants ####
###################


IMAGE_SIZE_P5  = 5175296   # 5 MB ProFile hard drive image size in bytes.
IMAGE_SIZE_P10 = 10350592  # 10 MB ProFile hard drive image size in bytes.

SECTOR_SIZE = 532  # Sector size in bytes. Cf. "block size" in spare tables.

# This "secret" Cameo/Aphid device ID and protocol version is appended to the
# end of the sector $FFFFFF spare table data structure, allowing software to
# identify when a Cameo/Aphid is present (and how to talk to it). For major
# revisions to this protocol (which includes the format of writes to $FFFFFD
# and to various standard (whatever that means) "magic blocks" plugins),
# increment the 4-digit number at the end.
CAMEO_APHID_ID = b'Cameo/Aphid 0001'

# For the beginning of command messages that tell the Aphid PRU1 firmware to
# execute various operations, we use statistically-unusual sequences of bytes.
APHD_COMMAND_GET_PART_1 = b'\x8c\xa9\x37\xf1' + struct.pack('<HH', 0, 266)
APHD_COMMAND_GET_PART_2 = b'\x8c\xa9\x37\xf1' + struct.pack('<HH', 266, 266)
APHD_COMMAND_PUT_PART_1 = b'\xdb\x95\x4b\xc7' + struct.pack('<HH', 0, 354)
APHD_COMMAND_PUT_PART_2 = b'\xdb\x95\x4b\xc7' + struct.pack('<HH', 354, 354)
APHD_COMMAND_PUT_PART_3 = b'\xdb\x95\x4b\xc7' + struct.pack('<HH', 708, 356)
APHD_COMMAND_GOAHEAD = b'\xa6\x93\x73\xea' + struct.pack('<HH', 0, 0)

# Here are the various ProFile operations that we pretend to do.
PROFILE_READ = 0x00
PROFILE_WRITE = 0x01
PROFILE_WRITE_VERIFY = 0x02
PROFILE_WRITE_FORCE_SPARE = 0x03
ALL_PROFILE_WRITE_COMMANDS = (
    PROFILE_WRITE, PROFILE_WRITE_VERIFY, PROFILE_WRITE_FORCE_SPARE)

# Paths to the filesystem objects that allow us to configure the pinmux.
OCP_PREFIX = '/sys/devices/platform/ocp/'
GPIO_PREFIX = '/sys/class/gpio/gpio'

# Paths to the filesystem objects that allow us to choose PRU firmware.
PRU0_STATE_PATH = '/sys/class/remoteproc/remoteproc1/state'
PRU1_STATE_PATH = '/sys/class/remoteproc/remoteproc2/state'
PRU0_FW_CHOOSER_PATH = '/sys/class/remoteproc/remoteproc1/firmware'
PRU1_FW_CHOOSER_PATH = '/sys/class/remoteproc/remoteproc2/firmware'
PRU0_FW_NAME = 'aphd_pru0_datapump.fw'
PRU1_FW_NAME = 'aphd_pru1_control.fw'

# Paths to the filesystem objects that allow us to control LEDs.
LED_PREFIX = '/sys/class/leds/beaglebone:green:usr'

# The device we use to communicate with PRU1 over RPMsg
RPMSG_DEVICE = '/dev/rpmsg_pru31'

# Precomputed even parity lookup table.
PARITY = tuple(0x00 if bin(c).count('1') % 2 else 0xff for c in range(256))


##############################
#### Command-line parsing ####
##############################


def _define_flags() -> argparse.ArgumentParser:
  """Defines an `ArgumentParser` for command-line flags used by this program."""

  flags = argparse.ArgumentParser(description='Cameo/Aphid ProFile emulator.')
  flags.add_argument(
      '-d', '--device', type=str, default=RPMSG_DEVICE, help=(
          'Device file for the RPMsg connection to PRU 1. By default, this '
          'is {}.'.format(RPMSG_DEVICE)))
  flags.add_argument(
      '-v', '--verbose', action='store_true', help=(
          'Enable verbose logging.'))
  flags.add_argument(
      '-c', '--create', action='store_true', help=(
          'Create the empty hard drive image file image_file if it does not '
          'already exist.'))
  flags.add_argument(
      '--skip_pin_setup', action='store_true', help=(
          'Bypass the typical startup operation of configuring the I/O header '
          'pins. (Use this option if the header pins are pre-configured on '
          'boot by a device tree overlay.)'))
  flags.add_argument(
      '--skip_pru_restart', action='store_true', help=(
          'Bypass the typical startup cycle of stopping the PRUs, designating '
          'the firmware to run, and restarting the firmware. This option '
          'implies --skip_load_pru_firmware.'))
  flags.add_argument(
      '--skip_load_pru_firmware', action='store_true', help=(
          'Bypass the typical startup operation of designating the PRU '
          'firmware to run. (Use this option if the Cameo/Aphid PRU firmware '
          'is loaded automatically from /lib/firmware/am335x-pru0-fw and '
          '/lib/firmware/am335x-pru1-fw).'))
  flags.add_argument(
      'image_file', type=str, help=(
          'Path to the hard drive image file.'))

  return flags


# From here on, the code starts silly and gets more serious the further you go.

######################
#### LED blinking ####
######################


class LEDs:
  """Context manager and object for controlling the PocketBeagle user LEDs.

  On entry into the context, filehandles for the user LEDs are opened; on exit,
  they are closed. When in the context, the context manager itself can be used
  to turn LEDs on, turn them off, or cycle them through a blinking pattern.
  """

  def __enter__(self) -> 'LEDs':
    led_files = ['{}{}/brightness'.format(LED_PREFIX, i) for i in range(4)]
    self._leds = [open(lf, 'wb', buffering=0) for lf in led_files]
    # State for cycling the LEDs.
    self._current_in_cycle = 0   # Current state of the LED cycler.
    self._cycling_now = False    # Should we be cycling the LEDs right now?
    return self

  def __exit__(self, *ignored):
    del ignored  # Unused.
    for led in self._leds: led.close()

  def on(self):
    """All LEDs on, full blast."""
    for led in self._leds: led.write(b'255\n')

  def off(self):
    """All LEDs off, completely."""
    for led in self._leds: led.write(b'0\n')

  ### And now, cycling. Serious business! ###

  def cycle_one_step(self):
    """Execute one step of a cycling pattern."""
    self._leds[self._current_in_cycle].write(b'0\n')
    self._current_in_cycle = (self._current_in_cycle + 1) % len(self._leds)
    self._leds[self._current_in_cycle].write(b'255\n')

  def _cycle_while_allowed(self):
    """Cycle all four LEDs as long as a flag tells us we should."""
    while self._cycling_now:
      self.cycle_one_step()
      time.sleep(0.05)

  def cycle_forever(self):
    """Cycle all four LEDs till the end of time."""
    self._cycling_now = True
    self._cycle_while_allowed()

  def blink_forever(self):
    """Blink the centre two LEDs till the end of time."""
    self.off()
    while True:
      self._leds[1].write(b'255\n')
      self._leds[2].write(b'255\n')
      time.sleep(1.0)
      self._leds[1].write(b'0\n')
      self._leds[2].write(b'0\n')
      time.sleep(1.0)

  @contextlib.contextmanager
  def cycling_in_background(self) -> Iterator[None]:
    """Within this context, cycle the LEDs in a background thread."""
    if self._cycling_now: raise RuntimeError(
        'Attempted to start cycling LEDs whilst they were already cycling.')
    # Start cycling the LEDs in a background thread.
    self._cycling_now = True
    thread = threading.Thread(target=self._cycle_while_allowed)
    thread.daemon = True
    thread.start()

    try:
      yield  # Back to the caller.
    finally:
      # We're back. Stop the cycling now.
      self._cycling_now = False
      thread.join()


#####################################################
#### PocketBeagle hardware configuration helpers ####
#####################################################


def setup_pins():
  """Configure PocketBeagle pinmux configuration for Cameo/Aphid."""

  # These pins should be set for PRU input.
  for pin in ('P1_02', 'P1_30', 'P2_09'):
    logging.info('Configuring pin %s as pruin', pin)
    with open('{}ocp:{}_pinmux/state'.format(OCP_PREFIX, pin), 'w') as f:
      f.write('pruin\n')

  # These pins should be set for PRU output.
  for pin in ('P2_24', 'P2_35'):
    logging.info('Configuring pin %s as pruout', pin)
    with open('{}ocp:{}_pinmux/state'.format(OCP_PREFIX, pin), 'w') as f:
      f.write('pruout\n')

  # These pins should be set for GPIO, input direction. The GPIO numbers
  # appear to be 32 * <GPIO module number> + <GPIO bit>.
  for pin, gpio in (('P1_36', '110'), ('P1_33', '111'), ('P2_32', '112'),
                    ('P2_30', '113'), ('P1_31', '114'), ('P2_34', '115'),
                    ('P2_28', '116'), ('P1_29', '117')):
    logging.info('Configuring pin %s as GPIO, GPIO %s as input', pin, gpio)
    with open('{}ocp:{}_pinmux/state'.format(OCP_PREFIX, pin), 'w') as f:
      f.write('gpio\n')
    with open('{}{}/direction'.format(GPIO_PREFIX, gpio), 'w') as f:
      f.write('in\n')


def setup_pru_firmware(device, load_firmware=True):
  """Ensure PRU 0 and PRU 1 are running the Aphid firmware

  Stops any currently-running firmware running on the PRUs, directs the kernel
  to load the Aphid firmware, and starts that firmware.

  Args:
    device: The device file for the RPMsg connection to PRU 1. (Usually this is
        `/dev/rpmsg_pru31`.) After starting the firmware, this routine sends
        a meaningless message to PRU 1 to initiate its ordinary operation.
    load_firmware: If set, this routine will direct the kernel to load the
        firmware files `/lib/firmware/aphd_pru0_datapump.fw` and
        `/lib/firmware/aphd_pru1_control.fw` into the PRUs. Not necessary if the
        kernel is loading the firmware at boot time from
        `/lib/firmware/am335x-pru[01]-fw`.

  Raises:
    RuntimeError: Various errors in attempting to establish running firmware on
        the PRU, most relating to timeouts.
  """

  # Immediately after the PocketBeagle boots, the filesystem objects for
  # controlling PRUs may not be available. We wait on them for up to a minute.
  for _ in range(600):
    if all(os.path.exists(p) for p in [
        PRU0_STATE_PATH, PRU1_STATE_PATH,
        PRU0_FW_CHOOSER_PATH, PRU1_FW_CHOOSER_PATH]): break
    time.sleep(0.1)
  else:
    raise RuntimeError(
        'Gave up waiting for filesystem objects for PRU control to exist.')

  # Shut down any PRU firmware that might be running now.
  logging.info('Stopping any PRU firmware running now...')
  for i in (0, 1):
    try:
      with open([PRU0_STATE_PATH, PRU1_STATE_PATH][i], 'w') as f:
        f.write('stop\n')
    except IOError:
      logging.info("Couldn't stop PRU %d; maybe it's not running. "
                   'Carrying on...', i)

  if load_firmware:
    # Indicate which firmware we'd like to run the PRU.
    logging.info('Pointing remoteproc at the Aphid PRU firmware...')
    with open(PRU0_FW_CHOOSER_PATH, 'w') as f: f.write(PRU0_FW_NAME + '\n')
    with open(PRU1_FW_CHOOSER_PATH, 'w') as f: f.write(PRU1_FW_NAME + '\n')

  # Start the firmware.
  logging.info('Starting the Aphid PRU firmware...')
  with open(PRU0_STATE_PATH, 'w') as f: f.write('start\n')
  with open(PRU1_STATE_PATH, 'w') as f: f.write('start\n')

  # Wait for both PRUs to be up and running.
  for i in (0, 1):
    for _ in range(600):
      with open([PRU0_STATE_PATH, PRU1_STATE_PATH][i], 'r') as f:
        if f.read() == 'running\n': break
      time.sleep(0.1)
    else:
      raise RuntimeError('Gave up waiting on PRU {} firmware boot.'.format(i))

  if load_firmware:
    # Despite all these precautions, it seems necessary to wait a bit to be
    # assured that the PRU is ready for RPMsg communication, particularly after
    # reboots. This is an empirical finding. It probably depends on load :-(
    time.sleep(15.0)

  # The firmware waits for an RPMsg message in order to learn critical
  # identifiers for communicating back to the ARM. Here we send it a
  # meaningless message as soon as we can, or give up after a minute of trying.
  for _ in range(600):
    try:
      with open(device, 'w') as f: f.write('\n')
      break
    except IOError:
      time.sleep(0.1)
  else:
    raise RuntimeError('Gave up waiting to send a "bootup" message to PRU 1.')


###########################
#### RPMsg I/O helpers ####
###########################


class Rpmsg(NamedTuple(
    'Rpmsg', [('fd', int),
              ('poll_read', select.poll),
              ('poll_write', select.poll)])):
  """I/O-related objects for RPMsg communication with PRU1.

  Use `rpmsg_io_init` to initialise/prepare this data structure.

  Fields:
    fd: A prepared read-write file descriptor for an RPMsg device file.
    poll_read: For detecting when reads will not block.
    poll_write: For detecting when writes will not block.
  """


def rpmsg_io_init(fd: int) -> Rpmsg:
  """Prepare a file object for RPMsg I/O and derive `select.poll` objects.

  The argument file descriptor should be the device file used for two-way RPMsg
  communication with PRU1 running the Aphid PRU1 firmware. This descriptor will
  be set to non-blocking mode, and two `select.poll` objects (for blocking
  until it's OK to read/write) will be created for it.

  Args:
    fd: A file descrptor referring to the PRU1 RPMsg device file. This
        descriptor will be manipulated as described above.

  Returns:
    An Rpmsg object initialised from `fd`.
  """
  # Set reads on the device file object to non-blocking.
  os.set_blocking(fd, False)

  # Create select.poll objects for waiting on the file object
  # for both reading and writing.
  poll_read = select.poll()
  poll_read.register(fd, select.POLLIN)
  poll_write = select.poll()
  poll_write.register(fd, select.POLLOUT)

  # Pack all RPMsg I/O objects and return.
  return Rpmsg(fd, poll_read, poll_write)


def rpmsg_read(rpmsg: Rpmsg, length: int, delay: float = 5.0) -> bytes:
  """Read `length` bytes from PRU1 via RPMsg.

  When data from PRU1 is available, this function will attempt to read all of
  it, even beyond `length` bytes if more is available. This approach is meant
  to drain any "uncollected" data from previous transactions with the PRU,
  since communication with the Aphid firmware is meant to be totally
  synchronous. (Presumably any data left over would indicate some sort of
  failure in a previous transaction; this kind of cleanup is not expected to
  be typical.)

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.
    length: How many bytes to read.
    delay: How long in seconds to block while waiting for data from PRU1. A
        negative value means wait indefinitely.

  Returns:
    A bytes object of up to `length` bytes read from PRU1 via RPMsg.

  Raises:
    RuntimeError: Failed (probably timed out) whilst waiting for RPMsg data
        from PRU1.
  """
  # Unpack RPMsg I/O objects; compute delay in ms.
  fd, poll_read, _ = rpmsg
  delay = int(1000 * delay)

  # Wait for data to be ready to read.
  if poll_read.poll(delay) != [(fd, select.POLLIN)]: raise RuntimeError(
      'Waiting for data from PRU 1 on the RPMsg device was unsuccessful.')

  # Read as much data as possible, 2k at a time; drain the file descriptor.
  all_data_parts = []
  while True:
    data = os.read(fd, 2048)
    all_data_parts.append(data)
    if len(data) < 2048: break

  # Return just those bytes requested. If we have collected more than the
  # number of bytes requested, we assume the oldest ones are stale and only
  # return the most recent values.
  all_data = b''.join(all_data_parts)
  if len(all_data) != length: logging.warning(
      'Expected to read %d bytes from PRU1; read %d instead.',
      length, len(all_data))
  return all_data[-length:]


def rpmsg_write(rpmsg: Rpmsg, data: bytes, delay: float = 5.0):
  """Write `data` to PRU1 via RPMsg.

  Attempts (with some persistence) to write all of `data` to PRU1 via RPMsg.

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.
    data: bytes object of data to send to PRU1.
    delay: How long in seconds to block each time we wait until it is possible
        to write data to PRU1. A negative value means wait indefinitely.

  Raises:
    RuntimeError: Failed (probably timed out) whilst waiting for it to be
        possible to write RPMsg data to PRU1.
  """
  # Unpack RPMsg I/O objects; compute delay in ms.
  fd, _, poll_write = rpmsg
  delay = int(1000 * delay)

  # Write data out bit by bit.
  all_written = 0
  while all_written < len(data):
    written = os.write(fd, data[all_written:])

    if written <= 0:  # If nothing was written, let's wait until we can write.
      if poll_write.poll(delay) != [(fd, select.POLLOUT)]: raise RuntimeError(
          'Waiting to write to PRU 1 on the RPMsg device was unsuccessful.')
    else:  # Otherwise advance the write index.
      all_written += written


################################
#### Disk image I/O helpers ####
################################


def make_spare_table(image_size: int) -> bytes:
  """Compute sector $FFFFFF spare table data for a given size disk image.

  A read from a ProFile's block $FFFFFF returns a data structure called the
  "spare table". This data structure contains basic information about the type
  of the drive, basic parameters like the number of sectors it has, and lists
  of bad blocks and spare blocks in use (both empty for Cameo/Aphid). Spare
  tables created by this function also include a string that identifies the
  drive as a Cameo/Aphid and a version number for the protocol that the Apple
  uses to access Cameo/Aphid-specific features.

  Args:
    image_size: Size of the disk image (in bytes) from which the Cameo/Aphid
        will be serving hard drive data. A size of exactly 10350592 will yield
        a spare table indicating that the drive is a ProFile-10 (device name
        "PROFILE 10M  ", device number $000010, firmware revision $0404); other
        sizes present the drive as a 5 MB ProFile (device name "PROFILE      ",
        device number $000000, firmware revision $0398) whose number of
        available blocks is `image_size // 532`.

  Returns:
    The contents of the 532-byte "spare table" returned by a read to $FFFFFF.
  """
  profile_10 = image_size == IMAGE_SIZE_P10  # Is this image for a ProFile 10?
  num_blocks = image_size // SECTOR_SIZE
  logging.info('Using %s headers for this disk image file.',
               'ProFile-10' if profile_10 else 'default ProFile')
  return (
      (b'PROFILE 10M  ' if profile_10 else b'PROFILE      ') +  # Device name.
      (b'\x00\x00\x10'  if profile_10 else b'\x00\x00\x00') +   # Device number.
      (b'\x04\x04'      if profile_10 else b'\x03\x98') +       # Firmware rev.
      struct.pack('>L', num_blocks)[1:] +  # Number of blocks available.
      b'\x02\x14' +      # Block size. 532 bytes.
      b'\x20' +          # Spare blocks on device. 32 blocks.
      b'\x00' +          # Spare blocks allocated. 0 blocks.
      b'\x00' +          # Bad blocks allocated. 0 blocks.
      b'\xff\xff\xff' +  # End of the list of (no) spare blocks.
      b'\xff\xff\xff' +  # End of the list of (no) bad blocks. Spare table ends.
      CAMEO_APHID_ID     # Secret Cameo/Aphid device ID and protocol version :-)
  ) + bytes(SECTOR_SIZE - 32 - 16)


class Image(NamedTuple(
    'Image', [('image_file', BinaryIO),
              ('mapped', mmap.mmap),
              ('image_size', int),
              ('spare_table', bytes)])):
  """I/O-related objects for memory-mapped disk image files.

  Use `image_mmap` to initialise/prepare this data structure.

  Fields:
    image_file: A read-write handle for the disk image file. Don't modify the
        disk image file with this object; in fact, you probably shouldn't use
        it for anything.
    mapped: A writeable mmap object for the file's entire contents.
    image_size: Size of the disk image in bytes.
    spare_table: Sector $FFFFFF spare table contents for this disk image.
  """


@contextlib.contextmanager
def image_mmap(path: str, create: bool) -> Generator[Image, None, None]:
  """mmap (after optionally creating) the disk image file.

  A context manager that opens and mmaps the disk image file, optionally
  creating it beforehand if `create` is True and the file does not exist.
  (Created image files are always 5 MB ProFile images, but disk image files
  can be any size.) When control exits the context, the map is closed and the
  file is sync'd to disk.

  Args:
    path: Path to the image file.
    create: Boolean indicating whether to create the image file. If True,
        there must not be a file at `path`.

  Yields:
    An Image object initialised from `path`.
  """

  # Create the new image file if directed.
  if create:
    if os.path.isfile(path): raise IOError(
        "File {} already exists; won't overwrite it with a new disk "
        'image.'.format(path))
    with open(path, 'wb') as f:
      for s in range(IMAGE_SIZE_P5 // SECTOR_SIZE):
        f.write(bytes(SECTOR_SIZE))
      f.flush()

  # Measure the size of the image file and use that to create the data for the
  # spare table.
  image_size = os.stat(path).st_size
  logging.info('Mapping the %d-byte disk image file %s.', image_size, path)
  spare_table = make_spare_table(image_size)

  # Open and mmap the file to allow reads and writes. Yield the file object
  # and the memory. When the caller is done with it, aggressively save.
  with open(path, 'rb+') as bf:
    mem = mmap.mmap(bf.fileno(), length=image_size, access=mmap.ACCESS_WRITE)
    try:
      yield Image(bf, mem, image_size, spare_table)
    finally:
      mem.flush()
      mem.close()
      logging.info('Final disk image data flush complete. '
                   'Disk image file closed.')


class ImageFlusher:
  """Background disk-syncing for mmap'd disk images.

  This context manager manages a thread that forces changes to a mmap'd disk
  image file to disk (at least as much as Linux allows---the kernel source
  makes it look as if `mmap.mmap.flush()` should force this, but who knows).
  To avoid excessive writes to Flash media, a delay can be specified between
  successive writes.

  Code that changes data in the mmap'd file should call the `dirty` method on
  the `ImageFlusher` object created for (and obtained by) the `with` statement.
  The thread will save the data to disk at most `delay` seconds later (where
  `delay` is a constructor argument).

  NOTE: Disk-syncing is NOT triggered on exiting an `ImageFlusher` context.
  (It would be redundant with the sync upon leaving an `image_mmap` context.)
  """

  def __init__(self, image: Image, delay: float = 4.0) -> None:
    """Initialise an ImageFlusher.

    Args:
      image: An Image object returned by `image_mmap`.
      delay: Flush no more frequently than this often, in seconds.
    """
    self._image = image
    self._delay = delay
    self._event = threading.Event()  # "Must flush" -OR- "It's time to quit"
    self._cease = threading.Event()  # "It's time to quit"
    self._thread = None  # type: Optional[threading.Thread]

  def dirty(self):
    self._event.set()  # An event ("Time to flush to disk!") has occurred

  def __enter__(self) -> 'ImageFlusher':
    """Context manager entry. Create and run the flusher thread."""

    def thread():
      mem = self._image.mapped
      while True:
        self._event.wait()               # Wait for anything to happen
        if self._cease.is_set(): return  # Exit the thread if it's time to quit
        mem.flush()                      # Nope, time to flush, so flush
        logging.info('Disk image data flushed to the disk image file.')
        self._event.clear()              # Get ready for the next event
        # The next line: pause temporarily to avoid lots of writes.
        self._cease.wait(self._delay)    # But wake NOW if it's time to quit

    self._thread = threading.Thread(target=thread, name='flusher')
    self._thread.start()
    return self

  def __exit__(self, ex_type, ex_value, traceback):
    """Context manager exit. Shut down the flusher."""
    del ex_type, ex_value, traceback  # Unused
    self._cease.set()  # The flusher should shut down
    self._event.set()  # An event ("Shut down the flusher!") has occurred
    self._thread.join()


def image_get_sector(image: Image, sector: int) -> bytes:
  r"""Retrieve the `sector`th sector from the disk image.

  Args:
    image: An Image object returned by `image_mmap`.
    sector: Index of the sector to retrieve.

  Returns:
    532 bytes of sector data, or of b'\x00' bytes if the sector index is
    out-of-bounds. There is no failure for out-of-bounds sector indices.
  """
  start_index = sector * SECTOR_SIZE
  end_index = start_index + SECTOR_SIZE

  if start_index < 0 or end_index > image.image_size: return bytes(SECTOR_SIZE)
  return image.mapped[start_index:end_index]


def image_put_sector(
    image: Image,
    sector: int,
    data: bytes,
    flusher: Optional[ImageFlusher] = None,
):
  """Store sector data in the `sector`th sector of the disk image.

  The modified disk image data is committed to the image file as soon as
  possible.

  Args:
    image: An Image object returned by `image_mmap`.
    sector: Index of the sector receiving the data. Out-of-bounds sector
        indices are silently ignored with no effect on the disk image.
    data: 532-bytes of sector data to write to the `sector`th sector.
    flusher: Optional `ImageFlusher` object initialised with `image`.

  Raises:
    ValueError: `data` is not 532 bytes long.
  """
  mem = image.mapped
  if len(data) != SECTOR_SIZE: raise ValueError(
      'Sector data supplied to image_put_sector for sector {} was {} bytes '
      'long. It should be {} bytes.'.format(sector, len(data), SECTOR_SIZE))

  start_index = sector * SECTOR_SIZE
  end_index = start_index + SECTOR_SIZE
  if start_index < 0 or end_index > image.image_size: return

  mem[start_index:end_index] = data
  if flusher is not None:
    flusher.dirty()
  else:
    mem.flush()


#######################################
#### Aphid transactions over RPMsg ####
#######################################


def aphd_get_sector(rpmsg: Rpmsg) -> bytes:
  """Obtain contents of the Apple buffer from PRU1.

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.

  Returns:
    Contents of the Apple buffer on PRU1.

  Raises:
    RuntimeError: The attempt to read all 532 bytes failed.
  """
  # The transfer takes place in two parts, since the RPMsg data buffer is
  # too small to contain data for an entire sector.
  # Part 1: read the first 266 bytes of the buffer.
  rpmsg_write(rpmsg, APHD_COMMAND_GET_PART_1)
  part_1 = rpmsg_read(rpmsg, 266)
  # Part 2: read the second 266 bytes of the buffer.
  rpmsg_write(rpmsg, APHD_COMMAND_GET_PART_2)
  part_2 = rpmsg_read(rpmsg, 266)

  result = part_1 + part_2
  if len(result) != SECTOR_SIZE: raise RuntimeError(
      'An attempt to read the {}-byte Apple buffer from PRU1 via RPMsg has '
      'failed; {} bytes were read instead.'.format(SECTOR_SIZE, len(result)))
  return result


def aphd_put_sector(rpmsg: Rpmsg, data: bytes):
  """Store data (with added parity bytes) into the disk buffer on PRU1.

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.
    data: 532 bytes of data to store.

  Raises:
    ValueError: `data` was not exactly 532 bytes long.
  """
  if len(data) != SECTOR_SIZE: raise ValueError(
      'The data argument to aphd_put_sector was {} bytes long; it should be '
      '{} bytes.'.format(len(data), SECTOR_SIZE))

  # Compute parity bytes for the data to place in the drive sector.
  data = b''.join(bytes((c, PARITY[c])) for c in data)

  # The transfer takes place in three parts, since the RPMsg data buffer is
  # too small to contain data for an entire sector.
  # Part 1: write the first 354 bytes of the sector.
  command = APHD_COMMAND_PUT_PART_1 + data[:354]
  rpmsg_write(rpmsg, command)
  # Part 2: write the next 354 bytes of the sector.
  command = APHD_COMMAND_PUT_PART_2 + data[354:708]
  rpmsg_write(rpmsg, command)
  # Part 3: write the last 356 bytes of the sector.
  command = APHD_COMMAND_PUT_PART_3 + data[708:]
  rpmsg_write(rpmsg, command)


def aphd_goahead(rpmsg: Rpmsg):
  """Issue a "go ahead" command to PRU1.

  During reads and writes, PRU1 waits for this code to finish reading/writing
  data from/to its buffers. This command tells PRU1 that buffer activity has
  completed and PRU1 can resume the operation.

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.
  """
  # Assemble command structure and dispatch.
  rpmsg_write(rpmsg, APHD_COMMAND_GOAHEAD)


def aphd_await_command(rpmsg: Rpmsg) -> bytes:
  """Read a ProFile command from the Apple via PRU1.

  This wait blocks indefinitely. When a command is finally received, it is
  returned to the caller. The Aphid firmware will have handled much of the
  command on its own already; the command itself usually requires this program
  to exchange data between PRU1 and the disk image. See the `profile` function
  for details.

  Args:
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.

  Returns:
    The six byte command obtained from the Apple.

  Raises:
    RuntimeError: numerous attempts to read the command have failed.
  """
  for _ in range(600):
    command = rpmsg_read(rpmsg, 6, delay=-1.0)  # Negative delays last forever.
    if len(command) == 6: return command
  else:
    raise RuntimeError('Numerous attempts to read the 6-byte Apple command '
                       'from PRU1 have all failed.')


##########################
#### ProFile emulator ####
##########################


def profile(
    image: Image,
    rpmsg: Rpmsg,
    leds: LEDs,
    plugins: Optional[Dict[int, profile_plugins.Plugin]] = None,
    flusher: Optional[ImageFlusher] = None,
) -> bytes:
  """Emulator core; broker data exchange between the Aphid and the disk image.

  Does not return voluntarily. KeyboardInterrupt and select.error exceptions
  from this function should be treated as benign shutdown requests; all
  other exceptions are anomalous.

  Args:
    image: An Image object returned by `image_mmap`.
    rpmsg: An Rpmsg object returned by `rpmsg_io_init`.
    leds: An LEDs object.
    flusher: Optional `ImageFlusher` object initialised with `image`.

  Returns:
    A sector's worth of data when the Apple has commanded the emulator to end
    the emulation session. The Apple does this by issuing one of the write
    commands to sector $FFFFFD with a $FE write count and an $AF sparing
    threshold (similar but not identical to one of IDEFile's "magic writes").
    The 532 bytes of sector data associated with that write command are the
    "conclusion" returned by this function.

  Raises:
    KeyboardInterrupt: the emulator main loop has been interrupted by SIGTERM.
        A bit of a strange way to represent this event, but it should be
        handled the same way as a user's Ctrl-C.
  """
  # Set up signal handler that raises a KeyboardInterrupt on SIGTERM, allowing
  # us to shut down cleanly.
  def sigterm_handler(signal, frame):
    raise KeyboardInterrupt
  old_sigterm_handler = signal.signal(signal.SIGTERM, sigterm_handler)

  # Everything now takes place in a try: block so that we can restore the old
  # signal handler in a finally: before we exit this function.
  try:

    # If conclusion is set to a non-None value, then this function will return
    # the PRU to a nominal state (i.e. tell it to resume processing) and then
    # return this value, concluding the ProFile emulation session.
    conclusion = None  # type: Optional[bytes]

    # A read request for sector $FFFFFE obtains the contents of the ProFile's
    # memory buffer, which presumably is the last sector read from or written to
    # the drive. We keep track of the last sector coming or going so that we
    # can supply the same if requested.
    last_data = bytes(SECTOR_SIZE)

    # If the caller supplied no plugins, swap in an empty plugin dict.
    if plugins is None: plugins = {}

    # MAIN LOOP :-)
    logging.info('Cameo/Aphid ProFile emulator ready.')
    while conclusion is None:
      # Wait for a command from the Apple. Ignore unless it's six bytes long.
      leds.on()
      command = aphd_await_command(rpmsg)
      leds.off()
      if len(command) != 6: continue

      # Decode the command. Awkwardly, struct does not support unpacking
      # three-byte quantities like the sector identifier.
      op, sector_hi, sector_lo, retry_count, sparing_thresh = struct.unpack(
          '>BBHBB', command)
      sector = (sector_hi << 16) + sector_lo

      # For logging.
      hex_command = command.hex()

      # All we need to do is transfer data between PRU1 and the disk image
      # depending on whether we're being told to read or write.
      if op == PROFILE_READ:
        logging.info('[%s]  Read sector $%06X', hex_command, sector)
        if sector == 0xffffff:    # Get the spare table
          data = image.spare_table
        elif sector == 0xfffffe:  # Get the last data read or written
          data = last_data
        elif 0xff0000 <= sector < 0xffff00 and sector in plugins:  # Plugin call
          data = plugins[sector](op, sector, retry_count, sparing_thresh, None)  # type: ignore
          if len(data) != SECTOR_SIZE:                     # Enforce proper size
            data = data[:SECTOR_SIZE] + bytes(max(0, SECTOR_SIZE - len(data)))
        else:                     # Get a sector from the disk image
          data = image_get_sector(image, sector)
        aphd_put_sector(rpmsg, data)  # Send to PRU1

      elif op in ALL_PROFILE_WRITE_COMMANDS:
        logging.info('[%s] Write sector $%06X', hex_command, sector)
        data = aphd_get_sector(rpmsg)  # Get sector data from PRU1

        if (sector == 0xfffffd and    # Conclude this ProFile session
            retry_count == 0xfe and   # (That's 254.) This is opposite of the
            sparing_thresh == 0xaf):  # (That's 175.) IDEFile "magic numbers"
          conclusion = data
        elif 0xff0000 <= sector < 0xffff00 and sector in plugins:  # Plugin call
          _ = plugins[sector](op, sector, retry_count, sparing_thresh, data)
        else:                            # Just write this sector normally
          image_put_sector(image, sector, data, flusher)  # Stow in the disk img

      else:
        logging.warning('[%s] Unrecognised command, ignoring!', hex_command)

      # Tell the PRU to resume its processing.
      aphd_goahead(rpmsg)
      # Keep the last data read or written handy in case the Apple requests the
      # memory buffer contents.
      last_data = data

  # We're no longer in the main emulation loop. Restore the old SIGTERM handler.
  finally:
    signal.signal(signal.SIGTERM, old_sigterm_handler)

  # Assuming we exited without an exception, return the session conclusion data.
  return conclusion


def process_conclusion(
    last_image_file: str,
    conclusion: bytes,
) -> str:
  """Process the "conclusion" of an emulator session.

  An emulator session's _conclusion_ is the 532 bytes of sector data that the
  Apple supplied along with its command to end the emulation session (see the
  `profile` docstring). The main program uses this helper to parse this
  conclusion and perform any state changes that might be directed by its
  contents.

  This function may affect the state of the Cameo/Aphid stack, and it may
  return values that direct the main function to change that state.

  Args:
    last_image_file: The filename of the hard drive image file that was used
        during the prior emulation session.
    conclusion: Contents of the last emulator session's conclusion (see above).

  Returns:
    The filename of the hard drive image file that should be used during the
    next emulation session. Unless the conclusion is well-formed and directs
    otherwise, this will be the same as `last_image_file`.

  Raises:
    KeyboardInterrupt: the conclusion instructs Aphid to shut down cleanly.
  """
  # Convert the conclusion into a text string. Obeys null termination, ignores
  # the 532nd byte.
  command = conclusion[:conclusion.find(0)].decode(
      'raw_unicode_escape', errors='ignore')
  logging.info('Conclusion data: %s', command)

  if command == 'HALT':
    raise KeyboardInterrupt

  elif command.startswith('IMAGE:'):
    next_image_path, next_image_file = os.path.split(command[6:])
    if (next_image_path or                         # Files in cwd only.
        not next_image_file or                     # Must specify a file.
        not next_image_file.endswith('.image') or  # Must end in '.image'.
        not os.path.exists(next_image_file)):      # Must exist.
      return last_image_file
    else:
      return next_image_file

  else:
    return last_image_file


######################
#### Main program ####
######################


def main(FLAGS: argparse.Namespace):
  # Verbose logging if desired.
  if FLAGS.verbose: logging.getLogger().setLevel(logging.INFO)

  # We'll read/write to this image file.
  image_file = FLAGS.image_file

  # This will store the error that kills us.
  terminating_error = None  # type: Optional[BaseException]

  # Open the all-important LEDs.
  with LEDs() as leds:

    # Have the LEDs cycling in the background as we set things up.
    with leds.cycling_in_background():
      # Set up the pinmux for the Aphid firmware.
      if not FLAGS.skip_pin_setup: setup_pins()
      # (Re)start the Aphid firmware on the PRUs.
      if not FLAGS.skip_pru_restart: setup_pru_firmware(
          device=FLAGS.device,
          load_firmware=(not FLAGS.skip_load_pru_firmware))

    # Open the PRU RPMsg device file.
    fd = None  # type: Optional[int]
    try:
      fd = os.open(FLAGS.device, os.O_RDWR | os.O_DSYNC)
      # Initialise low-level I/O for RPMsg.
      rpmsg = rpmsg_io_init(fd)

      # Run back-to-back ProFile emulation sessions until there's an error.
      try:
        while True:
          # Load plugins, open disk image, commence a ProFile emulation session.
          logging.info('Loading "magic block" plugins...')
          with profile_plugins.plugins() as plugins:
            logging.info('Starting emulation with image file %s...', image_file)
            with image_mmap(image_file, FLAGS.create) as image:
              with ImageFlusher(image) as flusher:
                conclusion = profile(image, rpmsg, leds, plugins, flusher)
          # Process the session's "conclusion" before starting a new session.
          logging.info('Emulation session ended. Processing conclusion...')
          image_file = process_conclusion(image_file, conclusion)
      except (Exception, KeyboardInterrupt) as error:
        # Interrupted. image_mmap will have saved and flushed the image.
        terminating_error = error

    finally:
      if fd is not None: os.close(fd)

    # Just in case we didn't reinstall the signal handler in profile().
    signal.signal(signal.SIGTERM, signal.SIG_DFL)

    # All done now. Depending on the exception that interrupted us, cycle or
    # flash the LEDs so that in "headless" installations it's clearer when the
    # PocketBeagle has finally shut itself down.
    logging.info('Clean shutdown complete. (Ctrl-C again to exit.)')
    if isinstance(terminating_error, (KeyboardInterrupt, select.error)):
      leds.cycle_forever()  # An intentional shutdown: blink a rolling pattern
    else:
      logging.error('Anomalous exception: %s', terminating_error)
      leds.blink_forever()  # An unintentional shutdown: blink slowly


if __name__ == '__main__':
  flags = _define_flags()
  FLAGS = flags.parse_args()
  main(FLAGS)

#!/usr/bin/python3
"""Apple parallel port storage emulator for Cameo

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

When run atop the entire Cameo cape/Aphid PRU firmware stack, emulates a 5MB
ProFile hard drive. Backing storage is a 5,175,296-byte file mmap'd into this
program's process space.

Run with the --help flag for usage information.

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

from typing import BinaryIO, Generator, Iterator, Optional, Tuple, NamedTuple


###################
#### Constants ####
###################


IMAGE_SIZE = 5175296  # Hard drive image size in bytes.

SECTOR_SIZE = 532  # Sector size in bytes. Note "block size" in SPARE_TABLE.

SPARE_TABLE = (  # The sector $FFFFFF spare table for a healthy 5MB ProFile.
    b'PROFILE      '  # Device name. This indicates a 5MB ProFile.
    b'\x00\x00\x00'   # Device number. Also means "5MB ProFile".
    b'\x03\x98'       # Firmware revision $0398. (Latest sold?)
    b'\x00\x26\x00'   # Blocks available. 9,728 blocks.
    b'\x02\x14'       # Block size. 532 bytes.
    b'\x20'           # Spare blocks on device. 20 blocks.
    b'\x00'           # Spare blocks allocated. 0 blocks.
    b'\x00'           # Bad blocks allocated. 0 blocks.
    b'\xff\xff\xff'   # End of the list of (zero) spare blocks.
    b'\xff\xff\xff'   # End of the list of (zero) bad blocks.
) + bytes(532 - 32)

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
      '--skip_pru_restart', action='store_true', help=(
          'Bypass the typical startup cycle of stopping the PRUs, designating '
          'the firmware to run, and restarting the firmware.'))
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

    yield  # Back to the caller.

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


def boot_pru_firmware(device):
  """(Re)install Aphid firmware onto PRU0 and PRU1; (re)boot both."""

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
      logging.info("Couldn't stop PRU {}; maybe it's not running. "
                   'Carrying on...'.format(i))

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


class Image(NamedTuple(
    'Image', [('image_file', BinaryIO),
              ('mapped', mmap.mmap)])):
  """I/O-related objects for memory-mapped disk image files.

  Use `image_mmap` to initialise/prepare this data structure.

  Fields:
    image_file: A read-write handle for the disk image file. Don't modify the
        disk image file with this object; in fact, you probably shouldn't use
        it for anything.
    mapped: A writeable mmap object for the file's entire contents.
  """


@contextlib.contextmanager
def image_mmap(path: str, create: bool) -> Generator[Image, None, None]:
  """mmap (after optionally creating) the disk image file.

  A context manager that opens and mmaps the disk image file, optionally
  creating it beforehand if `create` is True and the file does not exist.
  When control exits the context, the map is closed and the file is sync'd
  to disk.

  Args:
    path: Path to the image file.
    create: Boolean indicating whether to create the image file. If True,
        there must not be a file at `path`.

  Yields:
    An Image object initialised from `path`.

  Raises:
    IOError: either this function was told to create an image file that already
        existed, or the specified image file was the wrong size.
  """

  # Create the new image file if directed.
  if create:
    if os.path.isfile(path): raise IOError(
        "File {} already exists; won't overwrite it with a new disk "
        'image.'.format(path))
    with open(path, 'wb') as f:
      for s in range(IMAGE_SIZE // SECTOR_SIZE):
        f.write(b'\x00' * SECTOR_SIZE)
      f.flush()

  # Check that the image file is the correct size.
  true_image_size = os.stat(path).st_size
  if true_image_size != IMAGE_SIZE: raise IOError(
      'File {} has size {}, but a real ProFile disk image should have '
      'size {}.'.format(path, true_image_size, IMAGE_SIZE))

  # Open and mmap the file to allow reads and writes. Yield the file object
  # and the memory. When the caller is done with it, aggressively save.
  with open(path, 'rb+') as bf:
    mem = mmap.mmap(bf.fileno(), length=IMAGE_SIZE, access=mmap.ACCESS_WRITE)
    yield Image(bf, mem)
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
      _, mem = self._image
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

  if start_index < 0 or end_index > IMAGE_SIZE: return b'\x00' * SECTOR_SIZE
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
  _, mem = image
  if len(data) != SECTOR_SIZE: raise ValueError(
      'Sector data supplied to image_put_sector for sector {} was {} bytes '
      'long. It should be {} bytes.'.format(sector, len(data), SECTOR_SIZE))

  start_index = sector * SECTOR_SIZE
  end_index = start_index + SECTOR_SIZE
  if start_index < 0 or end_index > IMAGE_SIZE: return

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
        handled the same way.
  """
  # Set up signal handler that stops the main loop on SIGTERM, allowing us
  # to shut down cleanly.
  caught_sigterm = False
  def sigterm_handler(signal, frame):
    caught_sigterm = True
  old_sigterm_handler = signal.signal(signal.SIGTERM, sigterm_handler)

  # If conclusion is set to a non-None value, then this function will return
  # the PRU to a nominal state (i.e. tell it to resume processing) and then
  # return this value, concluding the ProFile emulation session.
  conclusion = None  # type: Optional[bytes]

  # A read request for sector $FFFFFE obtains the contents of the ProFile's
  # memory buffer, which presumably is the last sector read from or written to
  # the drive. We keep track of the last sector coming or going so that we
  # can supply the same if requested.
  last_data = bytes(SECTOR_SIZE)

  # MAIN LOOP :-)
  logging.info('Cameo/Aphid ProFile emulator ready.')
  while conclusion is None and not caught_sigterm:
    # Wait for a command from the Apple. Ignore unless it's six bytes long.
    leds.on()
    command = aphd_await_command(rpmsg)
    leds.off()
    if len(command) != 6: continue

    # Decode the command. Awkwardly, struct does not support unpacking
    # three-byte quantities like the sector identifier.
    op, sector_hi, sector_lo, retry_count, sparing_threshold = struct.unpack(
        '>BBHBB', command)
    sector = (sector_hi << 16) + sector_lo

    # For logging.
    hex_command = command.hex()

    # All we need to do is transfer data between PRU1 and the disk image
    # depending on whether we're being told to read or write.
    if op == PROFILE_READ:
      logging.info('[%s]  Read sector $%06X', hex_command, sector)
      if sector == 0xffffff:    # Get the spare table
        data = SPARE_TABLE
      elif sector == 0xfffffe:  # Get the last data read or written
        data = last_data
      else:                     # Get a sector from the disk image
        data = image_get_sector(image, sector)
      aphd_put_sector(rpmsg, data)  # Send to PRU1

    elif op in [PROFILE_WRITE, PROFILE_WRITE_VERIFY, PROFILE_WRITE_FORCE_SPARE]:
      logging.info('[%s] Write sector $%06X', hex_command, sector)
      data = aphd_get_sector(rpmsg)  # Get sector data from PRU1

      if (sector == 0xfffffd and       # Conclude this ProFile session.
          retry_count == 0xfe and      # (That's 254.) This is opposite of the
          sparing_threshold == 0xaf):  # (That's 175.) IDEFile "magic numbers".
        conclusion = data
      else:                           # Just write this sector normally.
        image_put_sector(image, sector, data, flusher)  # Stow in the disk image

    else:
      logging.warning('[%s] Unrecognised command, ignoring!', hex_command)

    # Tell the PRU to resume its processing.
    aphd_goahead(rpmsg)
    # Keep the last data read or written handy in case the Apple requests the
    # memory buffer contents.
    last_data = data

  # Back outside of the main emulation loop. Restore the old SIGTERM handler.
  signal.signal(signal.SIGTERM, old_sigterm_handler)
  # If we actually caught SIGTERM, re-raise it to pretend we were ctrl-C'd.
  if caught_sigterm: raise KeyboardInterrupt
  # Otherwise, return the session conclusion data.
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
  command = conclusion[:conclusion.find(0)].decode(errors='ignore')
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
      setup_pins()
      # (Re)start the Aphid firmware on the PRUs.
      if not FLAGS.skip_pru_restart: boot_pru_firmware(FLAGS.device)

    # Open the PRU RPMsg device file.
    fd = None  # type: Optional[int]
    try:
      fd = os.open(FLAGS.device, os.O_RDWR | os.O_DSYNC)
      # Initialise low-level I/O for RPMsg.
      rpmsg = rpmsg_io_init(fd)

      # Run back-to-back ProFile emulation sessions until there's an error.
      try:
        while True:
          # Open disk image and commence a ProFile emulation session.
          logging.info('Starting emulation with image file %s...', image_file)
          with image_mmap(image_file, FLAGS.create) as image:
            with ImageFlusher(image) as flusher:
              conclusion = profile(image, rpmsg, leds, flusher)
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
      leds.cycle_forever()  # An intentional shutdown: blink a rolling pattern.
    else:
      logging.error('Anomalous exception: %s', terminating_error)
      leds.blink_forever()  # An unintentional shutdown: blink slowly.


if __name__ == '__main__':
  flags = _define_flags()
  FLAGS = flags.parse_args()
  main(FLAGS)

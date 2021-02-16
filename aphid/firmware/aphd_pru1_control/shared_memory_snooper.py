#!/usr/bin/python3
"""Apple parallel port storage emulator for Cameo

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

This script (which must be run with superuser privileges) is a debugging aid
for PRU firmware development. It reaches directly into system memory and
extracts the contents of various data structures and statistics accumulators
used by the PRU0 and PRU1 firmware. This information, which includes things
like control communications between the PRUs, totals of bytes transferred, and
the progress of PRU1 through the stages of its transactions with the Apple, is
presented in a textual display that is updated as rapidy as possible. Your
terminal or terminal program must support VT-100 escape codes in order for the
display to be intelligible.

This program will not iterate quickly enough to obtain a complete record of the
quantities it samples. Without this fidelity, the best ways to use this script
may include comparing the "look" of misbehaving firmware against normal
operation and investigating the state of the PRUs if they seem to have frozen
at some point.

No further guidance is offered here on how to interpret the on-screen
information displayed by this script.
"""


import collections
import mmap
import sys
import time

from typing import List


DISPLAY = """\
\x1b[H\x1b[J[Cameo/Aphid shared memory snooper]

    [Datapump]                       (bytes)           in          out
    Command: ..  Size: ....         succeeded   ..........   ..........
    Retcode: ..  Addr: ........     requested   ..........   ..........

  pump_rd(size=...., addr=........) =
  pump_wr(size=...., addr=........) =

  Apple: handshake = XX, command = ............  Drive: status = ........

  Control debug word = ....
    (finals) =
     dt (ms) =

  RPMsg debug word = ....
    (finals) =
     dt (ms) =

                                             [^C] reset + redraw   [^\\] quit"""


# Helper: parse a string of bytes as a little-endian integer
to_int = lambda x: int.from_bytes(x, byteorder='little', signed=False)


class ShmemViewer:
  """Wraps a shared memory object and interprets information inside."""

  START = 0x4a310000  # Start of the shared memory region
  SIZE = 2156  # Total size of the shared memory region

  class DataPumpCommand:
    """The DataPumpCommand data structure

    We use a separate container for this data structure so that copies out of
    the shared memory are as brief and atomic as possible---otherwise we might
    be more likely to have mixed data, like a stale return code paired with the
    command, size, and address parameters for the next executed command. This
    outcome is still quite possible; the approach here just makes it marginally
    less likely.

    This rigour might not be so critical for other data structures.
    """

    def __init__(self, mem: bytes):
      """Initialise a DataPumpCommand.

      Args:
        mem: The eight bytes that make up a DataPumpCommand structure.
      """
      self._mem = mem

    @property
    def return_code(self): return self._mem[0]
    @property
    def command(self): return self._mem[1]
    @property
    def size(self): return to_int(self._mem[2:4])
    @property
    def address(self): return to_int(self._mem[5:8])


  def __init__(self, mem: mmap.mmap):
    """Initialise a ShmemViewer.

    Args:
      mem: A shared memory region established with a Cameo/Aphid SharedMemory
          structure starting at location 0.
    """
    self._mem = mem

  @property
  def data_pump_command(self): return self.DataPumpCommand(self._mem[:8])

  @property
  def data_pump_statistics_read_bytes_requested(self): return self._long(8)
  @property
  def data_pump_statistics_read_bytes_succeeded(self): return self._long(12)
  @property
  def data_pump_statistics_write_words_requested(self): return self._long(16)
  @property
  def data_pump_statistics_write_words_succeeded(self): return self._long(20)

  @property
  def apple_handshake(self): return self._mem[24]
  @property
  def apple_command(self): return self._mem[26:32]

  @property
  def drive_status(self): return self._mem[32:40:2]  # omit parity bytes

  @property
  def drive_sector(self): return self._mem[40:1104:2]  # omit parity bytes
  @property
  def apple_sector(self): return self._mem[1104:1636]

  @property
  def bytes_with_parity(self): return self._mem[1636:2148]

  @property
  def control_debug_word(self): return self._word(2148)
  @property
  def last_control_debug_word(self): return self._word(2150)
  @property
  def rpmsg_debug_word(self): return self._word(2152)
  @property
  def last_rpmsg_debug_word(self): return self._word(2154)

  def _word(self, start: int) -> int:
    """Interpret a 16-bit unsigned int at this location."""
    return to_int(self._mem[start:start+2])

  def _long(self, start: int) -> int:
    """Interpret a 32-bit unsigned int at this location."""
    return to_int(self._mem[start:start+4])


#### MAIN PROGRAM ####


def main(argv):
  del argv  # not used

  # What time is it?
  start_time = time.time()
  # How long has this program been running in milliseconds?
  runtime_ms = lambda: int(1000 * (time.time() - start_time))
  # And formatting that into four characters or fewer?
  ms_to_text = lambda x: '≥10k' if x >= 1000 else f'{x:4d}'

  def update_stream(stream: List[str], item: str) -> str:
    if len(stream) >= 14: del stream[11:]
    stream.insert(0, f'{item} ' if len(stream) % 3 else f'{item},')
    return ''.join(stream[:12])

  # These accumulators gather information that shows history and that allows
  # us to detect changes that require updating the display.
  last_data_pump_total = 0
  pump_rd_code_stream = []
  pump_wr_code_stream = []

  last_last_cdebug_word = -1
  last_last_cdebug_time = 0
  last_last_rdebug_word = -1
  last_last_rdebug_time = 0

  cdebug_final_stream = []
  cdebug_times_stream = []
  rdebug_final_stream = []
  rdebug_times_stream = []

  # Open the memory file for reading only, then map the portion of it that
  # contains the shared memory information we need into our memory space.
  with open('/dev/mem', 'rb') as devmem:
    with mmap.mmap(devmem.fileno(), ShmemViewer.SIZE,
                   mmap.MAP_SHARED, mmap.PROT_READ,
                   offset=ShmemViewer.START) as mem:
      view = ShmemViewer(mem)

      # Outer display loop: clears and redraws the screen on each pass.
      while True:
        sys.stdout.write(DISPLAY)  # Flushing happens in the inner loop.

        # Inner display loop: makes only local changes to the display.
        # Interrupting with ctrl-C will return us to the outer loop, where we
        # redraw the entire display.
        try:
          while True:
            # Get current (as current as possible) data pump details
            dpump_command = view.data_pump_command
            rbytes_requested = view.data_pump_statistics_read_bytes_requested
            rbytes_succeeded = view.data_pump_statistics_read_bytes_succeeded
            wbytes_requested = view.data_pump_statistics_write_words_requested
            wbytes_succeeded = view.data_pump_statistics_write_words_succeeded

            # Update immediate values. It's intentional that we update the pump
            # command last: it sets the cursor up for updating the data pump
            # return code stream.
            sys.stdout.write(
                f'\x1b[4;14H{dpump_command.command:02X}'
                f'\x1b[8C{dpump_command.size:04X}'
                f'\x1b[21C{rbytes_succeeded:10d}   {wbytes_succeeded:10d}'
                f'\x1b[5;14H{dpump_command.return_code:02X}'
                f'\x1b[8C{dpump_command.address:08X}'
                f'\x1b[17C{rbytes_requested:10d}   {wbytes_requested:10d}'
                f'\x1b[10;22H{view.apple_handshake:02X}'
                f'\x1b[12C{view.apple_command.hex().upper()}'
                f'\x1b[18C{view.drive_status.hex().upper()}'
                f'\x1b[12;24H{view.control_debug_word:04X}'
                f'\x1b[16;22H{view.rpmsg_debug_word:04X}')

            # Identify the datapump operation last executed. Command bytes
            # greater than 127 are bit-inverted copies of completed commands, so
            # we un-invert them.
            dpump_op = dpump_command.command
            if dpump_op > 0x7f: dpump_op = 0xff - dpump_op

            # We print and collect further datapump statistics if the command
            # is recognisable as a read or a write.
            if dpump_op < 2:
              sys.stdout.write(
                  f'\x1b[{8 if dpump_op else 7};16H'
                  f'{dpump_command.size:04X}\x1b[7C{dpump_command.address:08X}'
                  '\x1b[4C')

              # Update the data pump return code stream if necessary.
              data_pump_total = rbytes_requested + wbytes_requested
              if data_pump_total != last_data_pump_total:
                if dpump_command.return_code != 0xff:
                  last_data_pump_total = data_pump_total
                  stream = (pump_wr_code_stream
                            if dpump_op else
                            pump_rd_code_stream)
                  sys.stdout.write(update_stream(
                      stream, f'{dpump_command.return_code:02X}'))

            # Collect "last debug words"
            now = runtime_ms()
            last_cdebug_word = view.last_control_debug_word
            last_rdebug_word = view.last_rpmsg_debug_word

            # Update the control debug finals stream if necessary.
            if last_cdebug_word != last_last_cdebug_word:
              delta = now - last_last_cdebug_time
              last_last_cdebug_word = last_cdebug_word
              last_last_cdebug_time = now

              word_stream_text = update_stream(
                  cdebug_final_stream, f'{last_cdebug_word:04X}')
              time_stream_text = update_stream(
                  cdebug_times_stream, ms_to_text(delta))

              sys.stdout.write(
                  f'\x1b[13;16H{word_stream_text}\x1b[14;16H{time_stream_text}')

            # Update the RPMsg debug finals stream if necessary.
            if last_rdebug_word != last_last_rdebug_word:
              delta = now - last_last_rdebug_time
              last_last_rdebug_word = last_rdebug_word
              last_last_rdebug_time = now

              word_stream_text = update_stream(
                  rdebug_final_stream, f'{last_rdebug_word:04X}')
              time_stream_text = update_stream(
                  rdebug_times_stream, ms_to_text(delta))

              sys.stdout.write(
                  f'\x1b[17;16H{word_stream_text}\x1b[18;16H{time_stream_text}')

            # Finally: commit all our updates.
            sys.stdout.flush()

        # For ctrl-C breaking out of the inner loop.
        except KeyboardInterrupt:
          pass


if __name__ == '__main__':
  main(sys.argv)

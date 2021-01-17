"""A ProFile "magic block" plugin for Cameo/Aphid system information.

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

This plugin allows the Apple to obtain some basic system information from a
Cameo/Aphid.

By convention, this plugin is associated with block $FFFEFD. There's no reason
it can't be attached to different blocks, but for the following $FFFEFD will be
used as a shorthand for whatever "magic block" is in use.

Operations:

   - ProFile reads to $FFFEFD: Retrieve information about the Cameo/Aphid. The
     data returned by this plugin has the following format:

        Bytes   0-9: DDDDHHMMSS ASCII uptime; days right-justified space padded
        Bytes 10-24: ASCII right-aligned space-padded filesystem bytes free
        Bytes 25-31: ASCII null-terminated 1-minute load average
        Bytes 32-38: ASCII null-terminated 5-minute load average
        Bytes 39-45: ASCII null-terminated 15-minute load average
        Bytes 46-50: ASCII null-terminated number of processes running
        Bytes 51-55: ASCII null-terminated number of total processes

   - ProFile writes to $FFFEFD: do nothing at all.
"""

import logging
import os

from typing import Optional

import profile_plugins


PROFILE_READ = 0x00   # The ProFile protocol op byte that means "read a block"


class SystemInfoPlugin(profile_plugins.Plugin):
  """System information plugin.

  See the file header comment for usage details.
  """

  def __call__(
      self,
      op: int,
      block: int,
      retry_count: int,
      sparing_threshold: int,
      data: Optional[bytes],
  ) -> Optional[bytes]:
    """Implements the protocol described in the file header comment."""
    # We simply log and ignore non-reads.
    if op != PROFILE_READ:
      logging.warning(
          'System info plugin: ignoring non-read operation %02X', op)
      return None

    # Collect the information that this plugin returns. First, system uptime:
    with open('/proc/uptime', 'r') as f:
      seconds_left = round(float(f.read().split(' ')[0]))
    u_days, seconds_left = divmod(seconds_left, 86400)
    u_hours, seconds_left = divmod(seconds_left, 3600)
    u_minutes, seconds_left = divmod(seconds_left, 60)
    uptime = '{:4d}{:02d}{:02d}{:02d}'.format(
        u_days, u_hours, u_minutes, seconds_left)

    # Filesystem bytes free.
    st_statvfs = os.statvfs('.')
    bytes_free = '{:15d}'.format(st_statvfs.f_bsize * st_statvfs.f_bavail)

    # System load.
    with open('/proc/loadavg', 'r') as f:
      l_1min, l_5min, l_15min, l_processes, _ = f.read().split(' ')
    l_running, l_total = l_processes.split('/')

    # Helper: convert to binary and zero-pad to the right.
    def encode_and_pad(s: str, l: int) -> bytes:
      se = s.encode()[:l-1]
      return se + bytes(l - len(se))

    data = b''.join([
        uptime.encode(),
        bytes_free.encode(),
        encode_and_pad(l_1min, 7),
        encode_and_pad(l_5min, 7),
        encode_and_pad(l_15min, 7),
        encode_and_pad(l_running, 5),
        encode_and_pad(l_total, 5),
    ])
    return data[:532] + bytes(max(0, 532 - len(data)))


# By calling plugin() within this module, the plugin service instantiates a
# new FilesystemOpsPlugin.
plugin = SystemInfoPlugin

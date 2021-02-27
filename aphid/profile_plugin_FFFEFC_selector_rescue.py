"""A ProFile "magic block" plugin for reinstalling the Cameo/Aphid Selector.

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

This plugin makes it easier to recover an installation of the Selector to the
current working directory. It also "serves" the contents of complete Selector
hard drive image files. The data for both operations come from (what in most
Cameo/Aphid installations is) read-only storage, which may make it more robust
to whatever mischief the user might inflict on their .image files.

Note that if the user upgrades the Selector in the current working directory by
hand (as they might do by copying a new Selector drive image onto the
CAMEO_APHID microSD card partition), it still won't change the Selector copies
that this plugin uses, and a restoration of an older version could feel like a
downgrade.

By convention, this plugin is associated with block $FFFEFC. There's no reason
it can't be attached to different blocks, but for the following $FFFEFC will be
used as a shorthand for whatever "magic block" is in use.

   - ProFile reads to $FFFEFC: have effects that depend on the 16-bit
     concatenation of the read's retry count and sparing threshold parameters.
     These are:

     - $FFFF: copy the contents of `selector.image` from the Zip archive
       `/home/debian/aphid/selector/selector.image.zip` to `profile.image` in
       the current working directory, then trigger the start of a new emulation
       session using `profile.image` as the current hard drive image. If a file
       called `profile.image` already exists, it will be renamed to
       `profile.backup-X.image`, where `X` is the first number counting up from
       0 that yields an unused filename. The block contents retrieved by this
       read are unspecified.

     - $0XXX: retrieve the $XXXth 532-byte block of `selector.image` from the
       Zip archive `/home/debian/aphid/selector/selector.image.zip`, or, if
       `selector.image` is less than ($XXX - 1) * 532 bytes long, a block of
       532 $00 bytes.

     - $1XXX: retrieve the $XXXth 532-byte block of `selector.3.5inch.dc42` from
       the Zip archive `/home/debian/aphid/selector/selector.3.5inch.dc42.zip`,
       or, if `selector.3.5inch.dc42` is less than ($XXX - 1) * 532 bytes long,
       a block of 532 $00 bytes.

     - $2XXX: retrieve the $XXXth 532-byte block of `selector.twiggy.dc42` from
       the Zip archive `/home/debian/aphid/selector/selector.twiggy.dc42.zip`,
       or, if `selector.twiggy.dc42` is less than ($XXX - 1) * 532 bytes long,
       a block of 532 $00 bytes.

   - ProFile writes to $FFFEFC: do nothing at all.

This plugin may be convenient for Lisa users who have accidentally overwritten
the Selector hard drive image that's usually distribted with Cameo/Aphid:
instead of shutting down their device and using a modern computer to manage
drive image files on the microSD card's CAMEO_APHID partition, the user can
type a brief program into the Lisa's memory via the boot ROM's Service Mode,
then execute it. An example of such a program (which can be placed in RAM at
any valid address at or above $800) is:

    223C 00FF FEFC 227C 00FE 0090 50C2 50C3 50C4 4ED1

This program will only affect a Cameo/Aphid that's plugged into the built-in
parallel port. It's intentionally designed to cause the Lisa to crash or
reboot, but this is harmless and gets you booting into the Selector faster.
The assembly code for this program is:

    MOVE.L  #$FFFEFC,D1  ; Read from block $FFFEFC
    MOVEA.L #$FE0090,A1  ; Point A1 at the boot ROM ProFile read routine
    ST.B    D2           ; Set a timeout count of $??FF
    ST.B    D3           ; Set a retry count parameter of $FF
    ST.B    D3           ; Set a sparing threshold parameter of $FF
    JMP     (A1)         ; Invoke the ProFile read routine

You might be able to tell that this code attempts to load the contents of block
$FFFEFC into the boot ROM, which the Lisa doesn't care for. Even though this
loading cannot succeed, the attempt will still do enough communication with the
drive to trigger the Selector drive image restoration process.
"""

import itertools
import logging
import os
import pathlib

from typing import Dict, Optional

import profile_plugins


PROFILE_READ = 0x00   # The ProFile protocol op byte that means "read a block"
SECTOR_SIZE = 532     # Sector size in bytes. Cf. "block size" in spare tables.

IMAGE_PROFILE = '/home/debian/aphid/selector/selector.image.zip'
IMAGE_3_5INCH = '/home/debian/aphid/selector/selector.3.5inch.dc42.zip'
IMAGE_TWIGGY = '/home/debian/aphid/selector/selector.twiggy.zip'


class SelectorRescuePlugin(profile_plugins.Plugin):
  """'Selector rescue' plugin.

  See the file header comment for usage details.
  """

  def __init__(self) -> None:
    """Initialise a SelectorRescuePlugin"""
    self._image_cache = {}  # type: Dict[str, bytes]

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

    # Collect and interpret the command.
    command = (retry_count << 8) + sparing_threshold

    if command == 0xffff:
      return self._restore_selector()
    elif command < 0x1000:
      return self._image_data(IMAGE_PROFILE, command)
    elif command < 0x2000:
      return self._image_data(IMAGE_3_5INCH, command - 0x1000)
    elif command < 0x3000:
      return self._image_data(IMAGE_TWIGGY, command - 0x2000)
    else:
      return bytes(SECTOR_SIZE)  # Return zero blocks for 0x3000 and higher

  def _restore_selector(self):
    """Restore `profile.image` as described in the file header comment."""
    import zipfile  # Import here to avoid delaying initial emulator start-up.

    # Load the disk image into memory; nevermind the cache. If it doesn't
    # exist, just return a zero block.
    if os.path.exists(IMAGE_PROFILE):
      with zipfile.ZipFile(IMAGE_PROFILE) as zf:
        data = zf.read(zf.namelist()[0])
    else:
      logging.warning('Selector restore abandoned: %s missing', IMAGE_PROFILE)
      return bytes(SECTOR_SIZE)

    # Deal with any existing profile.image file.
    old_name = pathlib.Path('profile.image')
    if old_name.exists():  # It'd be weird if it didn't...
      # Check that there's enough free space for another disk image.
      st_statvfs = os.statvfs('.')
      if len(data) > (st_statvfs.f_bsize * st_statvfs.f_bavail):
        logging.warning('Selector restore abandoned: insufficient drive space')
        return bytes(SECTOR_SIZE)  # Give up if there isn't enough room.

      # Identify the safe new name for the current profile.image, and rename it.
      for i in itertools.count():
        new_name = f'profile.backup-{i}.image'
        if not os.path.exists(new_name):
          logging.info('Selector restore: moving %s to %s', old_name, new_name)
          old_name.rename(new_name)
          break

    # Write the new profile.image.
    with open(old_name, 'wb') as f:
      f.write(data)
    logging.info('Selector restore: wrote %s from %s', old_name, IMAGE_PROFILE)

    # Now raise the Conclusion exception that will start a new emulator
    # session that reads 'profile.image'.
    logging.info('Selector restore: triggering a new emulation session')
    raise profile_plugins.Conclusion(b'IMAGE:' + bytes(old_name))

  def _image_data(self, path: str, block: int) -> bytes:
    """Retrieve a block from a disk image stored in a Zip archive.

    Args:
      path: Full path to a Zip file whose only (or at least first) archived
          file is a disk image.
      block: Which 532-byte block to retrieve from the disk image.

    Returns:
      The specified 532-byte block from the disk image, or a block of 0x00
      bytes if the disk image can't be opened or has fewer than `block` blocks.
    """
    import zipfile  # Import here to avoid delaying initial emulator start-up.

    # Load the disk image into cache if it isn't there already. If the image
    # archive doesn't exist, just return zeros.
    if path not in self._image_cache:
      if os.path.exists(path):
        with zipfile.ZipFile(path) as zf:
          self._image_cache[path] = zf.read(zf.namelist()[0])
        logging.info('Selector rescue plugin: loaded %s', path)
      else:
        logging.warning('Selector rescue plugin: failed to read %s', path)
        return bytes(SECTOR_SIZE)

    # Retrieve the specified block from the disk image.
    start = block * SECTOR_SIZE
    end = start + SECTOR_SIZE
    data = self._image_cache[path][start:end]
    return data + bytes(SECTOR_SIZE - len(data))


# By calling plugin() within this module, the plugin service instantiates a
# new SelectorRescuePlugin.
plugin = SelectorRescuePlugin

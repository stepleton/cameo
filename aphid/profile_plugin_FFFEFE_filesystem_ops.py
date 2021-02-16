"""A ProFile "magic block" plugin for filesystem operations.

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

This plugin allows the Apple to order Cameo/Aphid to perform some basic
filesystem operations on the current working directory. For safety, operations
may be limited to files with a particular suffix, and some files may also be
listed as entirely off-limits to manipulation.

By convention, this plugin is associated with block $FFFEFE. There's no reason
it can't be attached to different blocks, but for the following $FFFEFE will be
used as a shorthand for whatever "magic block" is in use.

Operations:

   - ProFile reads to $FFFEFE: Retrieve information about a file in the current
     working directory. The plugin maintains a list of files (usually limited
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
     on the Apple can download a complete directory listing to present to the
     user. Programs that do this should save the nonce value at the beginning
     of one of the replies, which will change if and only if the contents of
     the current working directory change: as long as the nonce stays the same,
     the program will not need to download a new directory listing.

     (This strategy will not notice changes to file metadata like last-modified
     times or file sizes; the program will need to download a complete listing
     again if it's important to keep that data up-to-date.)

     If the program specifies an n greater than or equal to the number of
     (suffix-limited) files in the directory, the reply will list an empty
     0-byte file with a length-0 filename.

   - ProFile writes to $FFFEFE: Order the Cameo/Aphid to perform a filesystem
     operation in the current working directory, or change some aspect of the
     plugin's behaviour. Here, the 16-bit concatenation of the write's retry
     count and sparing threshold parameters direct which operation to perform,
     and the data contents are the parameters. Excess space in the parameter
     data may be padded arbitrarily.

     For readability, the 16-bit command is usually made of ASCII characters.
     Commands are:

     - 'cp': copy a file. Parameters are a null-terminated source filename and
       a null-terminated destination filename immediately following. There must
       be no existing file at the destination.

     - 'mv': move a file. Parameters are a null-terminated source filename and
       a null-terminated destination filename immediately following. There must
       be no existing file at the destination.

     - 'mk': create a new 5 MB ProFile disk image. The only parameter is a
       null-terminated filename for the new image. There must be no existing
       file by that name.

     - 'mx': "make extended": create a new disk image of arbitrary size.
       Parameters are a null-terminated numeric size string and a
       null-terminated filename for the new image immediately following. There
       must be no existing file by that name.

     - 'rm': remove a file. The only parameter is the null-terminated name of
       the file to remove.

     - 'sx': set the file suffix to the one null-terminated parameter. The
       plugin will only list or operate on files that end with this suffix.
       (For file extensions like '.image', you must include the '.' character.)
       It is valid to specify an empty suffix.

     The plugin gives no feedback about the success of any of these operations.
     For any that modify the filesystem, one workaround is to perform a read
     and see whether the nonce has changed.

     The plugin will do some validation to filenames listed as arguments,
     including checking for unprintable characters and '/', checking for the
     specified file suffix, and checking whether "target" filenames are
     off-limits. If it determines that a filename is invalid, it will abort the
     operation. This check may not be comprehensive, however, and it may still
     be possible for a malformed filename to crash the emulator!

Filenames are sent to and from the Apple in the ISO-8859-1 (Latin-1) character
encoding, but are transformed locally to UTF-8. Characters in UTF-8 that are
not present in Latin-1 will be escaped and decoded (ignoring errors) using
Python's "raw_unicode_escape" character codec.

NOTE: These escaped characters consume ten bytes each, and even single
filenames that use lots of them may not fit into a 532-byte ProFile block.
These filenames will be truncated, which may have unexpected side effects!
"""

import logging
import os
import pathlib
import shutil
import time

from typing import Callable, Iterable, Optional, Sequence, Tuple

import profile_plugins


IMAGE_SIZE = 5175296  # 5 MB ProFile hard drive image size in bytes.

PROFILE_READ = 0x00   # The ProFile protocol op byte that means "read a block"

# Any files with these names should not be touched by filesystem operations
# performed by this plugin, at least not by default.
PROTECTED_FILES = (
    'profile.image',                   # Cameo/Aphid default disk image
    'profile.py',                      # Cameo/Aphid emulator software
    'profile_plugins.py',              # Cameo/Aphid emulator plugin library
    'profile_key_value_store.db',      # Key/value store plugin data storage
    'profile_key_value_store.db.db',   # (Same, if dbm.ndbm is used)
    'profile_key_value_store.db.dat',  # (Same, if dbm.dumb is used)
    'profile_key_value_store.db.dir',  # (Same, if dbm.dumb is used)
    # And yeah, I guess we should avoid nuking the more popular plugins:
    'profile_plugin_FFFEFD_system_info.py',
    'profile_plugin_FFFEFE_filesystem_ops.py',
    'profile_plugin_FFFEFF_key_value_store.py',
)

# Command bytes that the Apple uses to specify a filesystem operation.
_COMMAND_COPY = int.from_bytes(b'cp', byteorder='big')  # Copy a file
_COMMAND_MOVE = int.from_bytes(b'mv', byteorder='big')  # Rename a file
_COMMAND_CREATE = int.from_bytes(b'mk', byteorder='big')  # Create a new image
_COMMAND_CREATE_EX = int.from_bytes(b'mx', byteorder='big')  # New image w/size
_COMMAND_DELETE = int.from_bytes(b'rm', byteorder='big')  # Delete a file
_COMMAND_SET_SUFFIX = int.from_bytes(b'sx', byteorder='big')  # Change suffix

_CODEC = 'raw_unicode_escape'  # For encoding Unix filenames for the Apple


class FilesystemOpsPlugin(profile_plugins.Plugin):
  """Filesystem operations plugin.

  See the file header comment for usage details.
  """

  def __init__(
      self,
      suffix: str = '.image',
      protected_files: Iterable[str] = PROTECTED_FILES,
  ) -> None:
    """Initialises a FilesystemOpsPlugin.

    Args:
      suffix: File limiting suffix. The plugin will not operate on files whose
          names do not end with this suffix. This suffix can be changed by
          the Apple through the 'sx' operation (see header comment).
      protected_files: A list of filenames that the plugin should never use as a
          "target" filename (i.e. the subject of any modifying change, like
          a copy/move destination or a filename for file creation/deletion).
    """
    self._suffix = suffix
    self._protected_files = set(protected_files)

    self._path = pathlib.Path('.')

    # To avoid scanning the directory with each new directory listing operation,
    # we cache files matching the suffix and only update them if the directory
    # mtime changes.
    self._mtime = 0x77  # Can't say 0: a mounted fat32 fs has a 0 mtime on boot
    self._files = ()  # type: Tuple[pathlib.Path, ...]
    self._maybe_update_file_list()

  def __call__(
      self,
      op: int,
      block: int,
      retry_count: int,
      sparing_threshold: int,
      data: Optional[bytes],
  ) -> Optional[bytes]:
    """Implements the protocol described in the file header comment."""
    # Operation is a read: retrieve a directory entry.
    if op == PROFILE_READ:
      return self._read(retry_count, sparing_threshold)

    # Operation is a write, with data.
    elif data is not None:
      if len(data) != 532: data = data[:532] + bytes(max(0, 532 - len(data)))
      self._write(retry_count, sparing_threshold, data)
      return None

    # Operation is something weird or malformed. Just return NULs.
    else:
      logging.warning(
          'Filesystem ops plugin: ignoring operation %02X with no data', op)
      return bytes(532)

  def _read(
      self,
      retry_count: int,
      sparing_threshold: int,
  ) -> bytes:
    """Retrieve the <retry_count><sparing_threshold>th file listing entry."""
    self._maybe_update_file_list()  # In case the directory contents changed.

    # We use the directory mtime as the nonce that tells the Apple whether to
    # flush its directory listing cache. Only the lower 32 bits of seconds are
    # used, but the Apple isn't supposed to care about the contents of the
    # nonce, so if it rolls over in 2038, it doesn't matter.
    dir_mtime_mod = self._mtime & 0xffffffff

    # Collect information about the filesystem entry queried by the Apple.
    index = (retry_count << 8) + sparing_threshold
    if index >= len(self._files):
      # The Apple is reading past the end of the files array, unfortunately.
      file_mtime_text = b'19700101000000'
      file_size_text = b'         0'
      file_name_text = b''
    else:
      # The Apple is interested in a perfectly legitimate file :-)
      entry = self._files[index]
      stat = entry.stat()
      file_mtime_text = bytes(
          time.strftime('%Y%m%d%H%M%S', time.gmtime(stat.st_mtime)),
          encoding=_CODEC)
      file_size_text = bytes('{:10d}'.format(stat.st_size), encoding=_CODEC)
      file_name_text = bytes(entry.name, encoding=_CODEC)

    # Assemble and return the file information record.
    data = b''.join([
        dir_mtime_mod.to_bytes(4, byteorder='big'),
        len(self._files).to_bytes(2, byteorder='big'),
        file_mtime_text,
        file_size_text,
        bytes(246),  # Reserved, unused for now
        file_name_text,
    ])
    return data[:532] + bytes(max(0, 532 - len(data)))

  def _write(
      self,
      retry_count: int,
      sparing_threshold: int,
      data: bytes,
  ) -> None:
    """Attempt a <retry_count><sparing_threshold> command from the Apple."""
    # Collect command and arguments; turn arguments into UTF-8.
    command = (retry_count << 8) + sparing_threshold
    args = tuple(a.decode(_CODEC, errors='ignore') for a in data.split(b'\x00'))

    # Helpers for argument checking:
    # Does the filename end with the right suffix?
    suffix_ok = lambda p: p.name.endswith(self._suffix)
    # Is it safe to alter the file?
    can_touch = lambda p: p.name not in self._protected_files

    # Process filesystem commands from the Apple.
    if command == _COMMAND_COPY:               # Copy a file
      if _check_filesystem_op_args(
          args,
          [suffix_ok, _cwa_file_exists],
          [suffix_ok, _cwa_does_not_exist, _cwa_name_ok, can_touch]):
        if _have_room(pathlib.Path(args[0]).stat().st_size):
          shutil.copyfile(args[0], args[1])

    elif command == _COMMAND_MOVE:             # Rename a file
      if _check_filesystem_op_args(
          args,
          [suffix_ok, _cwa_file_exists],
          [suffix_ok, _cwa_does_not_exist, _cwa_name_ok, can_touch]):
        pathlib.Path(args[0]).rename(args[1])

    elif command == _COMMAND_CREATE:           # Create a disk image-sized file
      if _check_filesystem_op_args(
          args,
          [suffix_ok, _cwa_does_not_exist, _cwa_name_ok, can_touch]):
        if _have_room(IMAGE_SIZE):
          with open(args[0], 'xb') as f: f.truncate(IMAGE_SIZE)

    elif command == _COMMAND_CREATE_EX:        # Create a file of specified size
      if args[0].isnumeric() and _check_filesystem_op_args(
          args[1:],
          [suffix_ok, _cwa_does_not_exist, _cwa_name_ok, can_touch]):
        if _have_room(int(args[0])):
          with open(args[0], 'xb') as f: f.truncate(int(args[0]))

    elif command == _COMMAND_DELETE:           # Delete a file
      if _check_filesystem_op_args(
          args,
          [suffix_ok, _cwa_file_exists, can_touch]):
        pathlib.Path(args[0]).unlink()

    elif command == _COMMAND_SET_SUFFIX:       # Set the current file suffix
      if _check_filesystem_op_args(
          args,
          [_cwa_name_ok]):
        self._suffix = args[0]
        # Force a refresh of the file listing.
        self._mtime -= 1
        self._maybe_update_file_list()

    else:                                      # Whatever dude...
      logging.warning(
          'Filesystem ops plugin: ignoring unrecognised command %04X', command)

  def _maybe_update_file_list(self) -> None:
    """Helper: check current dir mtime; update file list if needed."""
    new_mtime = int(self._path.stat().st_mtime)
    if self._mtime == new_mtime: return  # Our cache is up to date.

    self._mtime = new_mtime
    self._files = tuple(
        f for f in self._path.iterdir()
        if f.is_file and f.name.endswith(self._suffix))
    # Sort case-insensitively, but break ties in a case-sensitive way.
    self._files = tuple(sorted(self._files, key=lambda f: (str(f).lower(), f)))


def _check_filesystem_op_args(
    fs_op_args: Sequence[str],
    *all_checks: Sequence[Callable[[pathlib.Path], bool]]
) -> bool:
  """Helper: apply checks to filesystem operation arguments.

  A check is a callable that takes a `pathlib.Path` argument and returns True
  iff the argument satisfies some important condition. A few checks appear as
  lambdas at the bottom of this module.

  Will also return false if the number of entries in `fs_op_args` is fewer
  than the number of checks listed in *all_checks. Extra args, meanwhile, will
  be ignored.

  Args:
    fs_op_args: Filesystem operation arguments (note `str` type)
    *all_checks: Each *all_checks item is a collection of checks to be applied
        to each corresponding entry in `fs_op_args`.

  Returns:
    True iff each check returns True for its corresponding argument.
  """
  fs_op_args = fs_op_args[:len(all_checks)]
  if len(fs_op_args) != len(all_checks): return False
  if not all(fs_op_args): return False  # No blank args!

  for arg, checks in zip(fs_op_args, all_checks):
    if not all(check(pathlib.Path(arg)) for check in checks): return False
  return True


_cwa_file_exists = lambda p: p.exists() and p.is_file()  # Is a file that exists
_cwa_does_not_exist = lambda p: not p.exists()  # Nothing has that filename
_cwa_name_ok = lambda p: (p.name.isprintable() and '/' not in p.name  # Filename
                          and len(p.name.encode('utf-8')) <= 255)     # validity


def _have_room(image_size: int) -> bool:
  """Helper: is there room for a file of size `image_size` on this volume?"""
  st_statvfs = os.statvfs('.')
  return image_size <= (st_statvfs.f_bsize * st_statvfs.f_bavail)


# By calling plugin() within this module, the plugin service instantiates a
# new FilesystemOpsPlugin.
plugin = FilesystemOpsPlugin

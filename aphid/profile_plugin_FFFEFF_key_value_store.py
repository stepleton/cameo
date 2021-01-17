"""A ProFile "magic block" plugin providing a permanent key/value store.

Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.

This plugin allows the Apple to read from and write to a durable key/value
store through ordinary ProFile disk I/O. This store is accessible no matter
which disk image is being served to the Apple. Keys are 20 bytes long; values
are 512 bytes long.

The facility presents as having a kind of volatile (that is, not retained
through system reboots) write-through cache where the 65,535 cache entries are
controllable by the Apple (as opposed to being controlled automatically, as
with a CPU cache for example). Cache keys are 16-bit values formed by the
concatenation of the retry count and the sparing threshold that the Apple
specifies during a ProFile read or a write. During reads, the Apple can only
request items from the cache, so it must have earlier directed the store to
have loaded data there from the durable key/value store. For writes, the Apple
specifies both a cache key and the 20-byte store key; the data will be saved in
both the cache and the durable store automatically.

By convention, this plugin is associated with block $FFFEFF. There's no reason
it can't be attached to different blocks, but for the following $FFFEFF will be
used as a shorthand for whatever "magic block" is in use.

Operations:

   - ProFile reads to $FFFEFF: Retrieve the cache entry assocated with the
     16-bit concatenation of the retry count and sparing threshold parameters
     specified in the read. The store key will be the first 20 bytes of the
     returned data; the value is the remaining 512 bytes.

   - ProFile writes to $FFFEFF with retry count and sparing threshold both set
     to $FF: Order the store to load key/value pairs into the cache. The data
     in the write has the following format:

         Byte      0: Number of key/value pairs to load (up to 24)

         Bytes   1-2: 2-byte key for the cache entry receiving the first value
         Bytes  3-22: 20-byte key of the value to load into that cache entry

         Bytes 23-24: 2-byte key for the cache entry receiving the second value
         Bytes 25-44: 20-byte key of the value to load into that cache entry

     And so on.

   - ProFile writes to $FFFEFF with any other retry count and sparing threshold
     parameters: Write data to the cache entry specified by the parameters and
     to the key/value store. The store key is the first 20 bytes of the data,
     and the value is the remaining 512 bytes.

From a logical perspective, any store keys not yet associated with any data are
paired with 512 $00 bytes, and any cache keys not yet associated with any data
are associated with 532 $00 bytes (in other words, an all-$00 20-byte key and
512 bytes of all-$00 data).

See the class comment at `KeyValueStore` for implementation details.
"""

import collections
import logging
import dbm

from typing import Dict, MutableMapping, Optional

import profile_plugins


PROFILE_READ = 0x00

_512_NULS = bytes(512)  # The data portion of an empty block.
_532_NULS = bytes(532)  # An entire empty block's worth of NULs.


class KeyValueStorePlugin(profile_plugins.FlushingPlugin):
  """DBM-backed key/value store plugin.

  See the file header comment for usage details.

  Durable storage for the key/value store makes use of the `dbm` library for
  I/O to a "DBM" database. The `dbm` library is a generic interface, so the
  actual library used for reads and writes and the format of the database file
  may vary.
  """

  def __init__(
      self,
      filename: str = 'profile_key_value_store.db',
      delay: float = 4.0,
  ) -> None:
    """Inititalises a KeyValueStorePlugin.

    Opens the DBM database file backing the durable key/value store and
    initialises an empty cache.

    Args:
      filename: Database file backing the durable key/value store.
      delay: How long to wait after writes to the database before syncing it
          to disk.
    """
    super().__init__(default_delay=delay)
    logging.info('Key/value store plugin: opening database at %s...', filename)
    self._db = dbm.open(filename, 'c')  # type: MutableMapping[bytes, bytes]
    self._cache = {}  # type: Dict[int, bytes]

  def __call__(
      self,
      op: int,
      block: int,
      retry_count: int,
      sparing_threshold: int,
      data: Optional[bytes],
  ) -> Optional[bytes]:
    """Implements the protocol described in the file header comment."""
    cache_key = (retry_count << 8) + sparing_threshold

    # Operation is a read: withdraw an item from cache.
    if op == PROFILE_READ:
      return self._cache.setdefault(cache_key, _532_NULS)

    # Operation is a write, with data.
    elif data is not None:
      if len(data) != 532: data = data[:532] + bytes(max(0, 532 - len(data)))

      if cache_key == 0xffff:  # Operation wants us to move data into the cache
        for i in range(min(24, data[0])):         # Only 24 cache requests fit
          req = data[(1 + i * 22):(23 + i * 22)]  # Retrieve the i'th request
          req_cache_key = (req[0] << 8) + req[1]  # Which cache entry to fill
          req_store_key = req[2:]                 # What to fill it with
          self._cache[req_cache_key] = (          # Pull in the data
              req_store_key + self._db.setdefault(req_store_key, _512_NULS))
        return None
      else:                    # Operation just wants us to write
        self._cache[cache_key] = data    # Store data in the cache
        self._db[data[:20]] = data[20:]  # Store data in the store; TODO: lock?
        self.dirty()                     # Flush the data to disk eventually
        return None

    # Operation is something weird or malformed. Just return NULs.
    else:
      logging.warning(
          'Key/value store plugin: ignoring operation %02X with no data', op)
      return _532_NULS

  def flush(self) -> None:
    """Flush: save pending permanent key/value store changes to disk."""
    self._db.sync()  # type: ignore

  def close(self) -> None:
    """Close: close the permanent key/value store."""
    self.cancel()
    logging.info('Key/value store plugin: closing database')
    self._db.close()  # type: ignore


# By calling plugin() within this module, the plugin service instantiates a
# new KeyValueStorePlugin.
plugin = KeyValueStorePlugin

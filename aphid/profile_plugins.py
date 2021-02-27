r"""ProFile "magic block" plugins library for the Cameo/Aphid ProFile emulator.

The ProFile hard drive protocol allows the computer to read and write to
logical blocks identified by 24-bit numbers in the range $000000..$FFFFFD.
A hard drive providing storage for that many distinct block would store over
8 TiB of data, which would have been impressive to see in 1983.

Since no ordinary Apple II, Apple III, or Lisa software expects to access disk
blocks beyond 10 or so MiB, we can safely use larger block numbers for other
data transactions with the Cameo/Aphid emulator---including ones unrelated to
data storage altogether. For example, we could have successive reads from
$314159 supply us with 1,064 more BCD digits of pi---surely the ARM core on
the Cameo/Aphid would compute them much faster than the Lisa could.

A plugin system allows us to avoid hard-coding such "magic" features into
`profile.py`. A plugin is a Python single-file module whose name "fullmatches"
the regex

   profile_plugin_[0-9A-F]{6}.*\.py

where the six **uppercase** hexadecimal digits after `profile_plugin_` are the
block that the plugin will "enchant" with its own special handling of reads and
writes. The module should contain a zero-argument callable called `plugin` that
will return an instance of `Plugin` (defined below).  See the definition of
`Plugin` to understand what methods in this instance must do.

For now, only logical blocks $FF0000..$FFFEFF can be handled by plugins. If
the Cameo/Aphid plugin ecosystem ever requires more than 65,519 distinct block
addresses, the lower bound may be adjusted downward.

(As a final note, Cameo/Aphid does implement a few "magic" blocks natively.
$FFFFFF and $FFFFFE were already magical for the ProFile: they retrieve the
spare table and the ProFile's memory buffer respectively. Writes to $FFFFFD
can be used to restart or end ProFile emulation: see README.md for details.)
"""

import abc
import contextlib
import importlib.util
import logging
import pathlib
import threading

from typing import Dict, Generator, Optional


SECTOR_SIZE = 532  # Sector size in bytes. Cf. "block size" in spare tables.


class Plugin(abc.ABC):
  """Cameo/Aphid "magic block" plugin abstract base class.

  All plugins for the Profile emulator should subclass this class. Any resource
  allocation required for the plugin's operation (e.g. opening a file) should
  probably take place in its `__init__`.
  """

  @abc.abstractmethod
  def __call__(
      self,
      op: int,
      block: int,
      retry_count: int,
      sparing_threshold: int,
      data: Optional[bytes],
  ) -> Optional[bytes]:
    """Handle a ProFile I/O command from the Apple.

    Args:
      op: Operation requested by the Apple. $00 is a block read, and $01..$03
          are different kinds of writes (a plugin can treat all of these the
          same). This argument will take on no other values.
      block: Block requested by the Apple. This will always be the block
          selected by the module's filename.
      retry_count: Operation retry count specified by the Apple, a value in
          $00..$FF. The plugin can use this value as a parameter if desired.
      sparing_threshold: Operation sparing threshold specified by the Apple, a
          value in $00..$FF. The plugin can use this value as a parameter, too.
      data: If `op == $00`, then None. Otherwise, 532 bytes of data that the
          Apple expects to "write" to the block selected by `block`.

    Returns:
      If `op == $00`, then the return value should be 532 bytes of data "read"
      from the block. Otherwise any return value is ignored.
    """
    pass

  def close(self) -> None:
    """Cease operation of the plugin.

    This method will be called prior to emulator shutdown. Plugins should
    perform whatever operations here are necessary to ensure that essential
    data is saved and that other resources are gracefully retired. If no such
    operations are required, there's no need to implement this method.

    Remember that Cameo/Aphid is often shut down by cutting the power. Plugins
    that should be robust to sudden power cuts may benefit from inheriting
    from `FlushingPlugin`.
    """
    pass


class FlushingPlugin(Plugin):
  """A `Plugin` subclass for plugins that wish to "flush" after a time delay.

  This subclass simplifies the implementation of plugins that will want to
  perform some kind of delayed cleanup operation, such as saving information
  to the filesystem. Plugins can call the `dirty` method in their `__call__`,
  which will asynchronously call the `flush` method after a preset interval.

  If `dirty` is called again during the interval, the delay will be pushed
  back---reset to its original duration (unless a different delay is specified,
  in which case it is reset to that duration).

  The motivating circumstance is a plugin that commits changes to the
  filesystem. A write after every change would be slow and may risk wearing the
  solid-state storage media, so instead the plugin can call `dirty` after
  accumulating writes in a buffer. Once there is a period of low activity, the
  `flush` method will be called and buffered writes can be written all at once.
  """

  def __init__(self, default_delay: float = 4.0) -> None:
    """Initialise a FlushingPlugin.

    Args:
      default_delay: Default interval between the last call to `dirty` and
          a subsequent call to the `flush` method.
    """
    self._delay = default_delay
    self._timer = None  # type: Optional[threading.Timer]
    self._rlock = threading.RLock()
    self._abort = False

  @abc.abstractmethod
  def flush(self) -> None:
    """A method that is called some time after the last call to `dirty`."""
    pass

  def dirty(self, delay: Optional[float] = None) -> None:
    """Schedule a call to `flush` after some delay.

    Args:
      delay: The delay after which `flush` will be called, unless `dirty` is
          called again in the meantime. If unspecified, the `default_delay`
          parameter passed to the constructor is used.
    """
    with self._rlock:
      self.cancel()
      self._abort = False
      self._timer = threading.Timer(
          delay if delay is not None else self._delay,
          self._flush)

  def cancel(self) -> None:
    """Cancels a pending call to `flush`."""
    with self._rlock:
      self._abort = True
      if self._timer: self._timer.cancel()
      self._timer = None

  def _flush(self) -> None:
    """Helper for calling the user-implemented `flush` method."""
    with self._rlock:
      if self._abort: return
      self._timer = None
      self.flush()


def load_plugins(directory: str = '.') -> Dict[int, Plugin]:
  """Collect instantiated plugins from the specified directory.

  This function will attempt to load plugins from all files whose name
  "fullmatches" the regex

     profile_plugin_[0-9A-F]{6}.*\.py

  It will attempt to load these files as python modules and invoke a callable
  called `plugin` inside with no arguments. Exceptions that occur at any point
  when trying to load a module are logged and ignored.

  It us up to the caller to call these plugins' `close` methods when the
  plugins are no longer required. The `plugins` context manager in this module
  automates this process.

  Args:
    directory: Directory to load plugins from.

  Returns:
    All plugins loaded from the directory, keyed by the block number specified
    in their filenames.

  Raises:
    ValueError: `directory` was not a directory.
  """
  path = pathlib.Path(directory)
  if not path.is_dir(): raise ValueError(
      '{} is not a directory'.format(directory))

  plugins = {}  # type: Dict[int, Plugin]
  for item in path.glob('profile_plugin_??????*.py'):
    # Get block number for the plugin---again, all hex digits must be uppercase.
    hex_digits = item.name[15:21]
    if not all(d in '0123456789ABCDEF' for d in hex_digits): continue
    block = int(hex_digits, 16)

    # Try to load and instantiate the plugin. We log and ignore any exception.
    try:
      logging.info('Plugins: loading %s...', item.stem)
      module_spec = importlib.util.spec_from_file_location(item.stem, str(item))
      module = importlib.util.module_from_spec(module_spec)
      module_spec.loader.exec_module(module)  # type: ignore
      plugin = module.plugin()  # type: ignore
      plugins[block] = plugin
    except Exception:
      logging.exception('While attempting to load the plugin for block $%06X '
                        'from %s', block, item.name)

  return plugins


@contextlib.contextmanager
def plugins(directory: str = '.') -> Generator[Dict[int, Plugin], None, None]:
  """A context manager that loads and automatically closes plugins.

  Wraps `load_plugins` in a context manager that calls the `close` method on
  all loaded plugins at context exit. Exceptions raised by any `close` method
  are logged and ignored.

  Args:
    directory: Directory to load plugins from.

  Yields:
    The plugins dict returned by `load_plugins(directory)`.

  Raises:
    ValueError: `directory` was not a directory.
  """
  plugins = load_plugins(directory)
  try:
    yield plugins
  finally:
    for block, plugin in plugins.items():
      try:
        plugin.close()
      except Exception:
        logging.exception('While closing the plugin for block $%06X:', block)


class Conclusion(Exception):
  """An exception that concludes the current emulation session.

  A plugin that raises this exception in its __call__ method will cause the
  current emulation session to end, with the "conclusion" to the session being
  the result of truncating or zero-padding the `conclusion` bytes argument to
  the constructor to exactly 532 bytes.

  Study `process_conclusion` in `profile.py` to learn more about how data in
  these conclusions are interpreted by the emulator.

  The 532-byte read data provided to the Apple if a Conclusion is raised during
  a read is not specified. Cameo/Aphid may also not do anything at all with
  data it receives during a write operation that raises a Conclusion.

  Attributes:
    conclusion: A 532-byte value indicating what should happen when the current
        emulation session is ended.
  """
  conclusion: bytes

  def __init__(self, conclusion: bytes) -> None:
    """Initialise a Conclusion exception.

    Args:
      message: 
    """
    super().__init__()
    self.conclusion = (
        conclusion[:SECTOR_SIZE] + bytes(max(0, SECTOR_SIZE - len(conclusion))))

# Apple Parallel Hard Drive Emulator

The Apple Parallel Hard Drive Emulator is derived from the Cameo/Aphid cape
for the [PocketBeagle](http://beagleboard.org/pocket) single-board computer.
It is intended as a modified form-factor with some enhancements over the
cape design.

## Rev A

The Rev A design uses the same components as the cape, including two Texas
Instruments [TXS0108EPWR]( http://www.ti.com/product/TXS0108E) 8-bit bidirectional voltage
level translator ICs. The 100ohm resistors are included for better
compatibility with the Lisa 2/10, but YMMV. The board is designed to plug
directly into the parallel port without a cable.

## Rev B

The Rev B design forgoes the TXS0108 chips for BSS138 logic level converters.
This design has shown to be more compatible with the Apple Lisa 2/10 using the
internal widget cable. A small adapter can be used to convert from the 26-pin
IDC cable to the DB25 interface provided on the board.

## Other notes

In the spirit of Cameo, this modified design is released into the public domain.
There is no warranty and any improvements are welcome.

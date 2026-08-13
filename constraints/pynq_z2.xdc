## constraints/pynq_z2.xdc
## TinyRISC-TinyML -- PYNQ-Z2 (XC7Z020-1CLG400C) pin constraints.
##
## Pin numbers below are copied from the official PYNQ-Z2 reference XDC
## (TUL/Xilinx master constraints, cross-checked against the Xilinx/PYNQ
## base overlay's own base.xdc for the LED/button pins) -- not guessed
## from memory. Only the signals this project actually uses are
## uncommented; everything else on the board (HDMI, audio, Arduino/
## RaspberryPi headers, XADC, etc.) is intentionally left unconstrained.
##
## IMPORTANT -- UART routing: PYNQ-Z2's onboard USB-UART bridge is wired
## to the Zynq PS's MIO[14:15] pins, NOT to the PL fabric. Since this
## project is pure-PL (no PS7/ARM core used at all), the onboard USB
## cable CANNOT reach uart_tx/uart_rx below. UART is routed to PMOD JA
## pins 1/2 instead -- connect an external USB-to-serial adapter there
## (TX/RX/GND) for your terminal program, per the setup note at the
## bottom of this file.
##
## Clock strategy: the board's only PL-side oscillator is 125 MHz
## (sysclk, pin H16). A Clocking Wizard IP (see rtl/top/pynq_z2_top.v)
## divides this down to a clean 50 MHz, matching software's
## SYSTEM_CLOCK_HZ assumption exactly -- so no firmware recompilation is
## needed for hardware bring-up.

## ---- 125 MHz board oscillator (input to the Clocking Wizard) ----
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sysclk }]; #Sch=sysclk
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { sysclk }];

## ---- reset button (btn[0]) ----
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { btn0 }]; #Sch=btn[0]

## ---- LEDs (plain, not the RGB pair) -- AC-05, reflects RESULT ----
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; #Sch=led[0]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; #Sch=led[1]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; #Sch=led[2]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; #Sch=led[3]

## ---- UART, routed to PMOD JA pins 1/2 (see note above) ----
## ja_p[1] = Y18 -> uart_tx  (FPGA transmits; wire to adapter's RXD)
## ja_p[2] = Y16 -> uart_rx  (FPGA receives;  wire to adapter's TXD)
## Pmod JA pin 6 and 12 are 3.3V/GND respectively -- use pin 5 or 11 (GND)
## for the adapter's ground reference, NOT pin 6 (that's 3.3V supply).
set_property -dict { PACKAGE_PIN Y18   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; #PmodJA pin1 (ja_p[1])
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; #PmodJA pin2 (ja_p[2])

## =========================================================
## SETUP NOTE -- external USB-UART adapter wiring:
##   Adapter TXD  -> PYNQ-Z2 PmodJA pin 2 (uart_rx, Y16)
##   Adapter RXD  -> PYNQ-Z2 PmodJA pin 1 (uart_tx, Y18)
##   Adapter GND  -> PYNQ-Z2 PmodJA pin 5 or 11 (GND)
##   Adapter VCC  -> leave unconnected (PYNQ-Z2 is self-powered; do NOT
##                   also power it from the adapter)
## Set your terminal program (Phase 8) to whatever baud rate
## software/src/main.c's UART_BAUD_RATE macro specifies (115200 by
## default) -- SYSTEM_CLOCK_HZ=50000000 there already matches this XDC's
## Clocking Wizard output, so no firmware change is needed.
## =========================================================

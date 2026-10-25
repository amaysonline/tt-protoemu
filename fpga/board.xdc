## Template constraints. Copy the PACKAGE_PIN names from your board's master XDC file
## (Digilent and RealDigital publish one per board) and replace every XX below.

## clock: if you feed the board oscillator into a Clocking Wizard, constrain the
## oscillator pin here and let the wizard's IP constraints handle clk_50.
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports clk_50]
create_clock -name clk_50 -period 20.000 [get_ports clk_50]

set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports btn_reset]

## host SPI header (PMOD A)
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports host_sck]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports host_csn]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports host_mosi]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports host_miso]

## LEDs
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports led_irq]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports led_rx_ready]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports led_tx_ready]

## engine pins (PMOD B): epin[0] .. epin[7]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[0]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[1]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[2]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[3]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[4]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[5]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[6]}]
set_property -dict { PACKAGE_PIN XX  IOSTANDARD LVCMOS33 } [get_ports {epin[7]}]

## I2C lines need pull-ups. The FPGA's internal ones are weak (tens of kilo-ohms):
## fine for a first test on short wires, but fit real 4.7 k resistors for anything serious.
set_property PULLUP true [get_ports {epin[6]}]
set_property PULLUP true [get_ports {epin[7]}]

## host and engine inputs are asynchronous; the RTL synchronises them itself
set_false_path -from [get_ports {host_sck host_csn host_mosi epin[*]}]

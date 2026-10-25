#=====================================================================
# boolean.xdc - Real Digital Boolean board (Xilinx Spartan-7 XC7S50)
#
# PACKAGE_PIN values are left as FILL_IN on purpose: copy the real pin
# names out of the Boolean board Master XDC (Real Digital's
# "Boolean_Master.xdc") and paste them over each FILL_IN below.
# The trailing comment on each line says which board signal to look up.
#
# IOSTANDARD values are the usual LVCMOS33 for this board; confirm them
# against the Master XDC as well (some banks differ).
#=====================================================================

#---------------------------------------------------------------------
# Clock - 100 MHz system oscillator
#---------------------------------------------------------------------
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { clk }];         # clk        <- Master XDC: 100 MHz clock input (clk100mhz / sysclk)

# 100 MHz => 10.000 ns period. Name it so timing reports are readable.
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports { clk }];

#---------------------------------------------------------------------
# Reset - active-high pushbutton (synchronous reset inside the design)
#---------------------------------------------------------------------
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { rst }];         # rst        <- Master XDC: a pushbutton, e.g. btn[0]

#---------------------------------------------------------------------
# UART - to the on-board USB-UART bridge
#
# Watch the direction naming in the Master XDC: the board's "uart_rxd"
# is usually the bridge's receive pin, i.e. the FPGA's TRANSMIT output.
# Cross them if the link stays silent.
#---------------------------------------------------------------------
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }]; # uart_rx_pin <- Master XDC: serial data INTO the FPGA  (bridge TX)
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }]; # uart_tx_pin <- Master XDC: serial data OUT of the FPGA (bridge RX)

#---------------------------------------------------------------------
# LEDs - last received byte, led[0] = LSB
#---------------------------------------------------------------------
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[0] }];      # led[0]     <- Master XDC: LED 0 (LSB)
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[1] }];      # led[1]     <- Master XDC: LED 1
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[2] }];      # led[2]     <- Master XDC: LED 2
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[3] }];      # led[3]     <- Master XDC: LED 3
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[4] }];      # led[4]     <- Master XDC: LED 4
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[5] }];      # led[5]     <- Master XDC: LED 5
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[6] }];      # led[6]     <- Master XDC: LED 6
set_property -dict { PACKAGE_PIN FILL_IN IOSTANDARD LVCMOS33 } [get_ports { led[7] }];      # led[7]     <- Master XDC: LED 7 (MSB)

#---------------------------------------------------------------------
# Bitstream / configuration settings
#---------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

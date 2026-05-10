## =========================================================================
## Basys 3 Constraints — Speaker Authentication + FSK Modem
## =========================================================================
##
## Switch roles:
##   SW0  (V17) — debug_force_kaushik : force auth_denied regardless of NN vote
##   SW1  (V16) — debug_force_sindhu  : force auth_ok    regardless of NN vote
##   SW2  (W16) — (reserved / unused)
##   SW3  (W17) — debug_overlay_enable: show live K/S pie chart in ANALYZING state
##   SW4–SW12   — (unused)
##   SW13 (U1)  — FSK RX sensitivity bit 0  (wired to fsk_receiver.sensitivity[0])
##   SW14 (T1)  — FSK RX sensitivity bit 1  (wired to fsk_receiver.sensitivity[1])
##   SW15 (R2)  — SYSTEM RESET (active-high)
##
## NOTE: SW0 and SW1 are the debug_force_auth switches.
##       Both OFF = NN majority vote determines authentication normally.
##       Both ON simultaneously is undefined; SW1 (Sindhu) takes priority in RTL.
## =========================================================================

## -------------------------------------------------------------------------
## 1. System Clock (100 MHz)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## -------------------------------------------------------------------------
## 2. System Reset — SW15 (active-high)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports reset_btn]

## -------------------------------------------------------------------------
## 3. UART Audio Input — USB-RS232 RX pin
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports uart_rx]

## -------------------------------------------------------------------------
## 4. Switches
##    SW0  : debug_force_kaushik
##    SW1  : debug_force_sindhu
##    SW3  : debug_overlay_enable
##    SW13 : FSK sensitivity[0]
##    SW14 : FSK sensitivity[1]
##    SW15 : reset (constrained above)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN T2    IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN R3    IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN W2    IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
## sw[15] shares pin R2 with reset_btn — constrained via reset_btn above; sw[15] left unconnected

## -------------------------------------------------------------------------
## 5. Buttons (UI Navigation)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports btnC]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports btnU]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports btnD]
set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports btnL]
set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports btnR]

## -------------------------------------------------------------------------
## 6. LEDs — VU Meter (16-bit)
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3    IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3    IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3    IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3    IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3    IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN P1    IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN L1    IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## -------------------------------------------------------------------------
## 7. Pmod JA — Pmod MIC3 (SPI microphone — visuals + FSK receive)
##    JA1=CS  JA3=MISO  JA4=SCLK
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J1   IOSTANDARD LVCMOS33 } [get_ports mic_cs]
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports miso]
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports mic_sclk]

## -------------------------------------------------------------------------
## 8. Pmod JB — Pmod OLEDrgb (OLED Display)
##    JB1=CS  JB2=SDIN  JB4=SCLK  JB7=D/C#  JB8=RES#  JB9=VCCEN  JB10=PMODEN
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN A14   IOSTANDARD LVCMOS33 } [get_ports oled_cs]
set_property -dict { PACKAGE_PIN A16   IOSTANDARD LVCMOS33 } [get_ports oled_sdin]
set_property -dict { PACKAGE_PIN B16   IOSTANDARD LVCMOS33 } [get_ports oled_sclk]
set_property -dict { PACKAGE_PIN A15   IOSTANDARD LVCMOS33 } [get_ports oled_d_cn]
set_property -dict { PACKAGE_PIN A17   IOSTANDARD LVCMOS33 } [get_ports oled_resn]
set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports oled_vccen]
set_property -dict { PACKAGE_PIN C16   IOSTANDARD LVCMOS33 } [get_ports oled_pmoden]

## -------------------------------------------------------------------------
## 9. Pmod JC — Pmod DA2 (FSK Transmitter DAC SPI)
##    JC1=SYNC_N  JC2=DIN(MOSI)  JC4=SCLK
## -------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports dac_sync_n]
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports dac_mosi]
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports dac_sclk_out]

## -------------------------------------------------------------------------
## 10. Configuration & Voltage Settings
## -------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

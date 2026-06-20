###############################################################################
# Created by write_sdc
###############################################################################
current_design system
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 25.0000 [get_ports {clk}]
set_clock_transition 0.1500 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {VGND}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {VPWR}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {btn[0]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {btn[1]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {btn[2]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {btn[3]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {resetn_btn}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sd_miso}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sw[0]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sw[1]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sw[2]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sw[3]}]
set_input_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {uart_rx}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {VGND}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {VPWR}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[0]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[1]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[2]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[3]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[4]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[5]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[6]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte[7]}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {out_byte_en}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sd_cs_n}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sd_mosi}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {sd_sck}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {trap}]
set_output_delay 5.0000 -clock [get_clocks {clk}] -add_delay [get_ports {uart_tx}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0334 [get_ports {VGND}]
set_load -pin_load 0.0334 [get_ports {VPWR}]
set_load -pin_load 0.0334 [get_ports {out_byte_en}]
set_load -pin_load 0.0334 [get_ports {sd_cs_n}]
set_load -pin_load 0.0334 [get_ports {sd_mosi}]
set_load -pin_load 0.0334 [get_ports {sd_sck}]
set_load -pin_load 0.0334 [get_ports {trap}]
set_load -pin_load 0.0334 [get_ports {uart_tx}]
set_load -pin_load 0.0334 [get_ports {out_byte[7]}]
set_load -pin_load 0.0334 [get_ports {out_byte[6]}]
set_load -pin_load 0.0334 [get_ports {out_byte[5]}]
set_load -pin_load 0.0334 [get_ports {out_byte[4]}]
set_load -pin_load 0.0334 [get_ports {out_byte[3]}]
set_load -pin_load 0.0334 [get_ports {out_byte[2]}]
set_load -pin_load 0.0334 [get_ports {out_byte[1]}]
set_load -pin_load 0.0334 [get_ports {out_byte[0]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {VGND}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {VPWR}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {clk}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {resetn_btn}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {sd_miso}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {uart_rx}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {btn[3]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {btn[2]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {btn[1]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {btn[0]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {sw[3]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {sw[2]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {sw[1]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {sw[0]}]
###############################################################################
# Design Rules
###############################################################################
set_max_transition 2.5000 [current_design]
set_max_capacitance 0.2000 [current_design]
set_max_fanout 10.0000 [current_design]

# Ignore timing on asynchronous inputs
set_false_path -from [get_ports {btn[*]}]
set_false_path -from [get_ports {sw[*]}]

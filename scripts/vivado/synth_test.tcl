# Merged TCL Script

# Wrapper and System Verilog Files
read_verilog system.v
read_verilog axi_to_apb_bridge.v
read_verilog apb_interconnect.v
read_verilog crypto_cluster.v
read_verilog ../../picosoc/aead_mmap_wrapper.v
read_verilog ../../picosoc/simple_spi_master.v
read_verilog ../../picorv32.v
read_verilog ../../picosoc/simpleuart.v

# TinyJambu Core
read_verilog ../../picosoc/tinyjambu/tinyjambu_core.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_datapath.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_nlfsr.v
read_verilog ../../picosoc/tinyjambu/tinyjambu_fsm.v

# Xoodyak Core
read_verilog ../../picosoc/Xoodyak_old/xoodoo.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_n_rounds.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_rc.v
read_verilog ../../picosoc/Xoodyak_old/xoodoo_round.v
read_verilog ../../picosoc/Xoodyak_old/xoodyakcore.v

# GIFT-COFB Core
read_verilog ../../picosoc/GIFT_COFB/cofb_core.v
read_verilog ../../picosoc/GIFT_COFB/double_half_block.v
read_verilog ../../picosoc/GIFT_COFB/feedback_G.v
read_verilog ../../picosoc/GIFT_COFB/gift128_addroundkey.v
read_verilog ../../picosoc/GIFT_COFB/gift128_encrypt_top.v
read_verilog ../../picosoc/GIFT_COFB/gift128_keyschedule.v
read_verilog ../../picosoc/GIFT_COFB/gift128_permbits.v
read_verilog ../../picosoc/GIFT_COFB/gift128_round.v
read_verilog ../../picosoc/GIFT_COFB/gift128_roundconst.v
read_verilog ../../picosoc/GIFT_COFB/gift128_subcells.v
read_verilog ../../picosoc/GIFT_COFB/padding.v
read_verilog ../../picosoc/GIFT_COFB/pho.v
read_verilog ../../picosoc/GIFT_COFB/pho1.v
read_verilog ../../picosoc/GIFT_COFB/phoprime.v
read_verilog ../../picosoc/GIFT_COFB/triple_half_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_block.v
read_verilog ../../picosoc/GIFT_COFB/xor_topbar_block.v

# Constraints
read_xdc synth_system.xdc

# Synthesis and Implementation
synth_design -part XC7A100TCSG324-1 -top system -directive AreaOptimized_high
# NO PnR
# opt_design
# place_design
# route_design

# Reports
report_utilization -hierarchical -file report_util_test_system.rpt
report_utilization -cells [get_cells u_aead/u_cluster/u_cofb] -file report_util_test_giftcofb.txt
report_utilization -cells [get_cells u_aead/u_cluster/u_cofb/u_gift128/round_loop[*].gift_round/subcells] -file report_util_test_subcells.txt


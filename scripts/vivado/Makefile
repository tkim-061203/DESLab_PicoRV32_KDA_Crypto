VIVADO_BASE = /tools/Xilinx/Vivado/2024.2
VIVADO = $(VIVADO_BASE)/bin/vivado
XVLOG = $(VIVADO_BASE)/bin/xvlog
XELAB = $(VIVADO_BASE)/bin/xelab
GLBL = $(VIVADO_BASE)/data/verilog/src/glbl.v
IVERILOG ?= iverilog
VVP ?= vvp
TOOLCHAIN_PREFIX = /opt/riscv/bin/riscv64-unknown-elf-
CC = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy

export VIVADO

export RDI_VERBOSE = False

SIM_RTL = \
	system_tb.v \
	system.v \
	axi_to_apb_bridge.v \
	apb_interconnect.v \
	crypto_cluster.v \
	../../picosoc/aead_mmap_wrapper.v \
	../../picosoc/simple_spi_master.v \
	../../picorv32.v \
	../../picosoc/simpleuart.v \
	../../picosoc/tinyjambu/tinyjambu_core.v \
	../../picosoc/tinyjambu/tinyjambu_datapath.v \
	../../picosoc/tinyjambu/tinyjambu_nlfsr.v \
	../../picosoc/tinyjambu/tinyjambu_fsm.v \
	../../picosoc/Xoodyak_old/xoodoo.v \
	../../picosoc/Xoodyak_old/xoodoo_n_rounds.v \
	../../picosoc/Xoodyak_old/xoodoo_rc.v \
	../../picosoc/Xoodyak_old/xoodoo_round.v \
	../../picosoc/Xoodyak_old/xoodyakcore.v \
	../../picosoc/GIFT_COFB/cofb_core.v \
	../../picosoc/GIFT_COFB/double_half_block.v \
	../../picosoc/GIFT_COFB/feedback_G.v \
	../../picosoc/GIFT_COFB/gift128_addroundkey.v \
	../../picosoc/GIFT_COFB/gift128_encrypt_top.v \
	../../picosoc/GIFT_COFB/gift128_keyschedule.v \
	../../picosoc/GIFT_COFB/gift128_permbits.v \
	../../picosoc/GIFT_COFB/gift128_round.v \
	../../picosoc/GIFT_COFB/gift128_roundconst.v \
	../../picosoc/GIFT_COFB/gift128_subcells.v \
	../../picosoc/GIFT_COFB/padding.v \
	../../picosoc/GIFT_COFB/pho.v \
	../../picosoc/GIFT_COFB/pho1.v \
	../../picosoc/GIFT_COFB/phoprime.v \
	../../picosoc/GIFT_COFB/triple_half_block.v \
	../../picosoc/GIFT_COFB/xor_block.v \
	../../picosoc/GIFT_COFB/xor_topbar_block.v

help:
	@echo ""
	@echo "Simple synthesis tests:"
	@echo "  make synth_area_{small|regular|large}"
	@echo "  make synth_speed"
	@echo ""
	@echo "System (SD-boot):"
	@echo "  make synth_system          <- synthesis (1 lần, chỉ cần khi đổi RTL/bootloader)"
	@echo "  make bootloader.hex        <- rebuild bootloader nếu bootloader.c thay đổi"
	@echo "  make sim_system            <- RTL system test + throughput summary (skips SD test)"
	@echo ""
	@echo "Firmware update (KHÔNG cần synthesis lại):"
	@echo "  cd ../../firmware && make firmware"
	@echo "  cd ../../firmware && make write-sd SD_DEV=/dev/sdX"
	@echo "  (reset FPGA - bootloader tự đọc SD và load firmware)"
	@echo ""

synth_%:
	rm -f $@.log
	$(VIVADO) -nojournal -log $@.log -mode batch -source $@.tcl
	rm -rf .Xil fsm_encoding.os synth_*.backup.log usage_statistics_webtalk.xml
	-grep -B4 -A10 'Slice LUTs' $@.log
	-grep -B1 -A9 ^Slack $@.log && echo


synth_system: bootloader.hex

sim_system: bootloader.hex sim_app.hex
	$(IVERILOG) -g2012 -o system_tb.vvp $(SIM_RTL)
	$(VVP) system_tb.vvp $(SIM_ARGS) $(if $(VCD),+vcd,)

sim_app.elf: ../../firmware/app_crt0.S ../../firmware/firmware.c ../../firmware/firmware.ld
	$(CC) \
		-march=rv32i -mabi=ilp32 -Os -g \
		-ffreestanding -fno-builtin \
		-ffunction-sections -fdata-sections \
		-nostdlib -nostartfiles \
		-DSKIP_SD_TEST=1 \
		-Wl,--gc-sections \
		-T ../../firmware/firmware.ld \
		-o $@ \
		../../firmware/app_crt0.S \
		../../firmware/firmware.c \
		-lgcc

sim_app.bin: sim_app.elf
	$(OBJCOPY) -O binary $< $@

sim_app.hex: sim_app.bin
	python3 ../../firmware/makehex.py $< 4096 > $@


bootloader.hex: ../../firmware/bootloader.c ../../firmware/boot_crt0.S ../../firmware/bootloader.ld
	$(CC) \
		-march=rv32i -mabi=ilp32 -Os -g \
		-ffreestanding -fno-builtin \
		-nostdlib -nostartfiles \
		-T ../../firmware/bootloader.ld \
		-o bootloader_tmp.elf \
		../../firmware/boot_crt0.S \
		../../firmware/bootloader.c
	$(OBJCOPY) -O binary bootloader_tmp.elf bootloader_tmp.bin
	python3 ../../firmware/makehex.py bootloader_tmp.bin 1024 > bootloader.hex
	rm -f bootloader_tmp.elf bootloader_tmp.bin
	@echo "[BOOT] bootloader.hex ready (1024 words = 4 KB)"
	@echo "[INFO] Re-synthesize Vivado project để nạp bootloader mới vào bitfile"

# -------------------------------------------------------
# firmware.hex (legacy — chỉ dùng cho sim, KHÔNG dùng cho synth_system)
# Nếu không cần sim có thể xóa target này
# -------------------------------------------------------
firmware.hex: firmware.S firmware.c firmware.lds
	$(CC) -Os -ffreestanding -nostdlib \
		-mabi=ilp32 -march=rv32i \
		-o firmware.elf firmware.S firmware.c \
		--std=gnu99 \
		-Wl,-Bstatic,-T,firmware.lds,-Map,firmware.map,\
--strip-debug,--build-id=none -lgcc
	$(OBJCOPY) -O binary firmware.elf firmware.bin
	python3 ../../firmware/makehex.py firmware.bin 4096 > firmware.hex

# -------------------------------------------------------
tab_%/results.txt:
	bash tabtest.sh $@

area: synth_area_small synth_area_regular synth_area_large
	-grep -B4 -A10 'Slice LUTs' \
		synth_area_small.log \
		synth_area_regular.log \
		synth_area_large.log

clean:
	rm -rf .Xil/
	rm -f firmware.bin firmware.elf firmware.hex firmware.map
	rm -f bootloader.hex bootloader_tmp.elf bootloader_tmp.bin
	rm -f sim_app.elf sim_app.bin sim_app.hex system_tb.vvp system.vcd
	rm -rf synth_*.log synth_*.mmi synth_*.bit synth_system.v
	rm -rf table.txt tab_*/ webtalk.jou
	rm -rf webtalk.log webtalk_*.jou webtalk_*.log
	rm -rf xelab.* xsim[._]* xvlog.*

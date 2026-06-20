`timescale 1 ns / 1 ps

module system_tb;
	reg clk = 1'b0;
	always #5 clk = ~clk;

	reg resetn_btn = 1'b0;
	reg [3:0] sw = 4'b0;
	reg [3:0] btn = 4'b0;
	reg uart_rx = 1'b1;
	reg sd_miso = 1'b1;

	wire trap;
	wire [7:0] out_byte;
	wire out_byte_en;
	wire uart_tx;
	wire sd_cs_n;
	wire sd_sck;
	wire sd_mosi;

	integer i;
	integer cycle_count = 0;

	system #(
		.UART_TX_HOLDOFF(16'd32)
	) uut (
		.clk        (clk),
		.resetn_btn (resetn_btn),
		.trap       (trap),
		.out_byte   (out_byte),
		.out_byte_en(out_byte_en),
		.sw         (sw),
		.btn        (btn),
		.uart_tx    (uart_tx),
		.uart_rx    (uart_rx),
		.sd_cs_n    (sd_cs_n),
		.sd_sck     (sd_sck),
		.sd_mosi    (sd_mosi),
		.sd_miso    (sd_miso)
	);

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("system.vcd");
			$dumpvars(0, system_tb);
		end

		#1;
		for (i = 0; i < 16; i = i + 1)
			uut.boot_mem[i] = 32'h0000_0013;
		uut.boot_mem[0] = 32'h0001_02b7; // lui t0, 0x10  -> 0x0001_0000
		uut.boot_mem[1] = 32'h0002_8067; // jalr x0, t0, 0
		$readmemh("sim_app.hex", uut.app_mem);

		repeat (100) @(posedge clk);
		resetn_btn <= 1'b1;
	end

	always @(posedge clk) begin
		cycle_count <= cycle_count + 1;

		if (cycle_count == 0 || (cycle_count % 1000000 == 0)) begin
			$display("[TB] cycle=%0d pc=0x%08x trap=%0b uart_we=%0b",
				cycle_count,
				uut.cpu.picorv32_core.reg_pc,
				trap,
				uut.uart_we);
		end

		if (uut.uart_we) begin
			$write("%c", uut.uart_tx_data);
			$fflush();
		end

		if (out_byte_en && out_byte == 8'hff) begin
			$display("\n[TB] PASS");
			$finish;
		end

		if (out_byte_en && out_byte == 8'h55) begin
			$display("\n[TB] FAIL");
			$fatal(1);
		end

		if (trap) begin
			$display("\n[TB] Unexpected CPU trap at cycle %0d", cycle_count);
			$fatal(1);
		end

		if (cycle_count > 20000000) begin
			$display("\n[TB] TIMEOUT after %0d cycles", cycle_count);
			$fatal(1);
		end
	end
endmodule

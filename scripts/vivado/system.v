`timescale 1 ns / 1 ps
// ============================================================
// PicoSoC — AXI System Bus + APB Peripheral Bus
// ============================================================
// MEMORY MAP (firmware-compatible)
//   0x0000_0000 – 0x0000_0FFF  Boot BRAM  4 KB  (RO, on APB)
//   0x0001_0000 – 0x0001_3FFF  App  BRAM 16 KB  (RW, on AXI)
//   0x1000_0000                LED  out_byte     W
//   0x1000_0004                UART TX Data      W
//   0x1000_0008                UART RX Data      R
//   0x1000_000C                UART Status       R
//   0x1000_0010                UART Baud Divider R/W
//   0x2000_0000                Switches          R
//   0x2000_0004                Buttons           R
//   0x3000_0000 – 0x3000_008C  AEAD Wrapper (COFB/Xoodyak/TinyJAMBU)
//   0x6000_0000 – 0x6000_000C  SD SPI Master     R/W
// ============================================================

module system #(
    parameter BOOT_SIZE = 1024,           // 4 KB in words
    parameter APP_SIZE  = 4096,           // 16 KB in words
    parameter UART_TX_HOLDOFF = 16'd9000
)(
    input            clk,
    input            resetn_btn,
    output           trap,
    output reg [7:0] out_byte,
    output reg       out_byte_en,
    input      [3:0] sw,
    input      [3:0] btn,
    output           uart_tx,
    input            uart_rx,
    output           sd_cs_n,
    output           sd_sck,
    output           sd_mosi,
    input            sd_miso
);
    // --------------------------------------------------------
    // Power-on reset
    // --------------------------------------------------------
    reg [5:0] reset_cnt = 0;
    reg [2:0] resetn_sync = 3'b000;

    always @(posedge clk)
        resetn_sync <= {resetn_sync[1:0], resetn_btn};

    always @(posedge clk) begin
        if (!resetn_sync[2] && (&reset_cnt))
            reset_cnt <= 0;
        else if (!(&reset_cnt))
            reset_cnt <= reset_cnt + 1;
    end

    wire resetn = &reset_cnt;

    // --------------------------------------------------------
    // Switch / Button synchroniser
    // --------------------------------------------------------
    reg [3:0] sw_sync1, sw_sync2;
    reg [3:0] btn_sync1, btn_sync2;

    always @(posedge clk) begin
        sw_sync1  <= sw;        sw_sync2  <= sw_sync1;
        btn_sync1 <= btn;       btn_sync2 <= btn_sync1;
    end

    // --------------------------------------------------------
    // UART
    // --------------------------------------------------------
    wire        uart_dat_wait;
    wire [31:0] uart_dat_do;
    wire [31:0] uart_div_do;
    wire uart_rx_valid = (uart_dat_do != 32'hFFFF_FFFF);

    reg        uart_we;
    reg        uart_rx_rd;
    reg  [7:0] uart_tx_data;
    reg  [3:0] uart_div_we;
    reg [31:0] uart_div_di;
    reg        tx_busy;
    reg [15:0] tx_countdown;
    wire uart_tx_ready = !tx_busy;

    simpleuart #(.DEFAULT_DIV(868)) uart_inst (
        .clk        (clk),
        .resetn     (resetn),
        .ser_tx     (uart_tx),
        .ser_rx     (uart_rx),
        .reg_div_we (uart_div_we),
        .reg_div_di (uart_div_di),
        .reg_div_do (uart_div_do),
        .reg_dat_we (uart_we),
        .reg_dat_re (uart_rx_rd),
        .reg_dat_di ({24'b0, uart_tx_data}),
        .reg_dat_do (uart_dat_do),
        .reg_dat_wait(uart_dat_wait)
    );

    // --------------------------------------------------------
    // SD SPI Master
    // --------------------------------------------------------
    reg  [7:0] sdspi_tx_data;
    reg [15:0] sdspi_clkdiv;
    reg        sdspi_start;
    reg        sdspi_cs_n_reg;
    reg        sdspi_done_sticky;
    reg  [7:0] sdspi_rx_data_reg;
    wire [7:0] sdspi_rx_data;
    wire       sdspi_busy;
    wire       sdspi_done;

    simple_spi_master u_sdspi (
        .clk      (clk),
        .resetn   (resetn),
        .start    (sdspi_start),
        .tx_data  (sdspi_tx_data),
        .clkdiv   (sdspi_clkdiv),
        .cs_n     (sdspi_cs_n_reg),
        .rx_data  (sdspi_rx_data),
        .busy     (sdspi_busy),
        .done     (sdspi_done),
        .spi_sck  (sd_sck),
        .spi_mosi (sd_mosi),
        .spi_miso (sd_miso),
        .spi_cs_n (sd_cs_n)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            sdspi_done_sticky <= 0;
            sdspi_rx_data_reg <= 8'hFF;
        end else begin
            if (sdspi_start)  sdspi_done_sticky <= 0;
            if (sdspi_done) begin
                sdspi_done_sticky <= 1;
                sdspi_rx_data_reg <= sdspi_rx_data;
            end
        end
    end

    // --------------------------------------------------------
    // AEAD Wrapper — TinyJAMBU / Xoodyak / GIFT-COFB
    // APB slave @ 0x3000_0000, sel[1:0] chọn cipher
    // --------------------------------------------------------
    wire [31:0] aead_prdata;
    wire        aead_pready;

    aead_mmap_wrapper u_aead (
        .clk     (clk),
        .rst_n   (resetn),
        .psel    (apb_psel && psel_aead),
        .penable (apb_penable),
        .pwrite  (apb_pwrite),
        .paddr   (apb_paddr[11:0]),
        .pwdata  (apb_pwdata),
        .prdata  (aead_prdata),
        .pready  (aead_pready)
    );

    // --------------------------------------------------------
    // Memory (BRAM)
    // --------------------------------------------------------
    reg [31:0] boot_mem [0:BOOT_SIZE-1];
    initial $readmemh("bootloader.hex", boot_mem);
    reg [31:0] app_mem [0:APP_SIZE-1];

    // ========================================================
    // PicoRV32 CPU — AXI4-Lite Master
    // ========================================================
    wire        cpu_awvalid, cpu_wvalid, cpu_arvalid;
    wire [31:0] cpu_awaddr, cpu_wdata, cpu_araddr;
    wire [ 3:0] cpu_wstrb;
    wire [ 2:0] cpu_awprot, cpu_arprot;
    wire        cpu_bready, cpu_rready;

    wire        cpu_awready, cpu_wready, cpu_bvalid;
    wire        cpu_arready, cpu_rvalid;
    wire [31:0] cpu_rdata;

    picorv32_axi cpu (
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_axi_awvalid(cpu_awvalid), .mem_axi_awready(cpu_awready),
        .mem_axi_awaddr (cpu_awaddr),  .mem_axi_awprot (cpu_awprot),
        .mem_axi_wvalid (cpu_wvalid),  .mem_axi_wready (cpu_wready),
        .mem_axi_wdata  (cpu_wdata),   .mem_axi_wstrb  (cpu_wstrb),
        .mem_axi_bvalid (cpu_bvalid),  .mem_axi_bready (cpu_bready),
        .mem_axi_arvalid(cpu_arvalid), .mem_axi_arready(cpu_arready),
        .mem_axi_araddr (cpu_araddr),  .mem_axi_arprot (cpu_arprot),
        .mem_axi_rvalid (cpu_rvalid),  .mem_axi_rready (cpu_rready),
        .mem_axi_rdata  (cpu_rdata),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0),
        .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'b0),
        .trace_valid(), .trace_data()
    );

    // ========================================================
    // AXI INTERCONNECT — 1 Master × 2 Slaves
    // ========================================================
    // Slave 0 = RAM  (addr[31:16] == 0x0001)
    // Slave 1 = APB  (everything else)

    wire [31:0] decode_addr = cpu_awvalid ? cpu_awaddr : cpu_araddr;
    wire decode_is_ram = (decode_addr[31:16] == 16'h0001);

    reg  active_is_ram;
    reg  txn_active;
    always @(posedge clk) begin
        if (!resetn) begin
            txn_active <= 0;
        end else begin
            if (!txn_active && (cpu_awvalid || cpu_arvalid)) begin
                active_is_ram <= decode_is_ram;
                txn_active    <= 1;
            end
            if (txn_active && ((cpu_bvalid && cpu_bready) ||
                               (cpu_rvalid && cpu_rready)))
                txn_active <= 0;
        end
    end

    wire is_ram = txn_active ? active_is_ram : decode_is_ram;

    wire ram_awready, ram_wready, ram_bvalid;
    wire ram_arready, ram_rvalid;
    wire [31:0] ram_rdata;

    wire brg_awready, brg_wready, brg_bvalid;
    wire brg_arready, brg_rvalid;
    wire [31:0] brg_rdata;

    assign cpu_awready = is_ram ? ram_awready : brg_awready;
    assign cpu_wready  = is_ram ? ram_wready  : brg_wready;
    assign cpu_bvalid  = is_ram ? ram_bvalid  : brg_bvalid;
    assign cpu_arready = is_ram ? ram_arready : brg_arready;
    assign cpu_rvalid  = is_ram ? ram_rvalid  : brg_rvalid;
    assign cpu_rdata   = is_ram ? ram_rdata   : brg_rdata;

    wire ram_i_awv = cpu_awvalid &  is_ram;
    wire ram_i_wv  = cpu_wvalid  &  is_ram;
    wire ram_i_arv = cpu_arvalid &  is_ram;
    wire brg_i_awv = cpu_awvalid & ~is_ram;
    wire brg_i_wv  = cpu_wvalid  & ~is_ram;
    wire brg_i_arv = cpu_arvalid & ~is_ram;

    // ========================================================
    // AXI SLAVE 0 — RAM (App BRAM 16 KB)
    // ========================================================
    reg        ram_bvalid_r, ram_rvalid_r;
    reg [31:0] ram_rdata_r;

    wire ram_wr_accept = ram_i_awv && ram_i_wv && !ram_bvalid_r;
    wire ram_rd_accept = ram_i_arv && !ram_rvalid_r;

    assign ram_awready = ram_wr_accept;
    assign ram_wready  = ram_wr_accept;
    assign ram_bvalid  = ram_bvalid_r;
    assign ram_arready = ram_rd_accept;
    assign ram_rvalid  = ram_rvalid_r;
    assign ram_rdata   = ram_rdata_r;

    always @(posedge clk) begin
        if (!resetn) begin
            ram_bvalid_r <= 0;
            ram_rvalid_r <= 0;
        end else begin
            if (ram_bvalid_r && cpu_bready) ram_bvalid_r <= 0;
            if (ram_rvalid_r && cpu_rready) ram_rvalid_r <= 0;
            if (ram_wr_accept) begin
                if (cpu_wstrb[0]) app_mem[(cpu_awaddr-32'h0001_0000)>>2][ 7: 0] <= cpu_wdata[ 7: 0];
                if (cpu_wstrb[1]) app_mem[(cpu_awaddr-32'h0001_0000)>>2][15: 8] <= cpu_wdata[15: 8];
                if (cpu_wstrb[2]) app_mem[(cpu_awaddr-32'h0001_0000)>>2][23:16] <= cpu_wdata[23:16];
                if (cpu_wstrb[3]) app_mem[(cpu_awaddr-32'h0001_0000)>>2][31:24] <= cpu_wdata[31:24];
                ram_bvalid_r <= 1;
            end
            if (ram_rd_accept) begin
                ram_rdata_r  <= app_mem[(cpu_araddr - 32'h0001_0000) >> 2];
                ram_rvalid_r <= 1;
            end
        end
    end

    // ========================================================
    // AXI SLAVE 1 — AXI-to-APB Bridge
    // ========================================================
    wire        apb_psel, apb_penable, apb_pwrite;
    wire [31:0] apb_paddr, apb_pwdata;
    wire [ 3:0] apb_pstrb;
    wire [31:0] apb_prdata;
    wire        apb_pready;
    wire        apb_pslverr;

    axi_to_apb_bridge u_bridge (
        .clk        (clk),
        .resetn     (resetn),
        .s_awvalid  (brg_i_awv),
        .s_awready  (brg_awready),
        .s_awaddr   (cpu_awaddr),
        .s_wvalid   (brg_i_wv),
        .s_wready   (brg_wready),
        .s_wdata    (cpu_wdata),
        .s_wstrb    (cpu_wstrb),
        .s_bvalid   (brg_bvalid),
        .s_bready   (cpu_bready),
        .s_arvalid  (brg_i_arv),
        .s_arready  (brg_arready),
        .s_araddr   (cpu_araddr),
        .s_rvalid   (brg_rvalid),
        .s_rready   (cpu_rready),
        .s_rdata    (brg_rdata),
        .PCLK       (),
        .PRESETn    (),
        .PADDR      (apb_paddr),
        .PSEL       (apb_psel),
        .PENABLE    (apb_penable),
        .PWRITE     (apb_pwrite),
        .PWDATA     (apb_pwdata),
        .PSTRB      (apb_pstrb),
        .PRDATA     (apb_prdata),
        .PREADY     (apb_pready),
        .PSLVERR    (apb_pslverr)
    );

    // ========================================================
    // APB INTERCONNECT — Address decode + PRDATA/PREADY mux
    // ========================================================
    wire psel_rom;
    wire psel_uart;
    wire psel_input;
    wire psel_aead;
    wire psel_sdspi;

    assign psel_rom   = (apb_paddr[31:12] == 20'h00000);   // 0x0000_0xxx
    assign psel_uart  = (apb_paddr[31:12] == 20'h10000);   // 0x1000_0xxx
    assign psel_input = (apb_paddr[31:12] == 20'h20000);   // 0x2000_0xxx
    assign psel_aead  = (apb_paddr[31:12] == 20'h30000);   // 0x3000_0xxx
    assign psel_sdspi = (apb_paddr[31:12] == 20'h60000);   // 0x6000_0xxx

    reg [31:0] prdata_uart, prdata_input, prdata_sdspi;

    reg [31:0] rom_rdata_r;
    always @(posedge clk) begin
        if (psel_rom && !apb_penable)
            rom_rdata_r <= boot_mem[apb_paddr[11:2]];
    end

    assign apb_prdata =
        psel_rom   ? rom_rdata_r  :
        psel_uart  ? prdata_uart  :
        psel_input ? prdata_input :
        psel_aead  ? aead_prdata  :
        psel_sdspi ? prdata_sdspi : 32'h0;

    // AEAD wrapper có pready riêng; các slave khác luôn ready
    assign apb_pready  = psel_aead ? aead_pready : 1'b1;
    assign apb_pslverr = 1'b0;

    // ========================================================
    // APB READ DATA — Combinational mux per peripheral
    // ========================================================
    always @* begin
        case (apb_paddr[4:0])
            5'h08:   prdata_uart = uart_dat_do;
            5'h0C:   prdata_uart = {30'b0, uart_rx_valid, uart_tx_ready};
            5'h10:   prdata_uart = uart_div_do;
            default: prdata_uart = 32'h0;
        endcase
    end

    always @* begin
        case (apb_paddr[2:0])
            3'h0:    prdata_input = {28'b0, sw_sync2};
            3'h4:    prdata_input = {28'b0, btn_sync2};
            default: prdata_input = 32'h0;
        endcase
    end

    always @* begin
        case (apb_paddr[3:0])
            4'h0:    prdata_sdspi = {24'd0, sdspi_rx_data_reg};
            4'h4:    prdata_sdspi = {29'd0, sdspi_cs_n_reg, sdspi_busy,
                                     sdspi_done_sticky};
            4'h8:    prdata_sdspi = {31'd0, sdspi_cs_n_reg};
            4'hC:    prdata_sdspi = {16'd0, sdspi_clkdiv};
            default: prdata_sdspi = 32'h0;
        endcase
    end

    // ========================================================
    // APB PERIPHERAL WRITE + READ side-effects
    // ========================================================
    wire apb_wr = apb_psel && apb_penable && apb_pwrite;
    wire apb_rd = apb_psel && apb_penable && !apb_pwrite;

    always @(posedge clk) begin
        if (!resetn) begin
            out_byte_en  <= 0;
            uart_we      <= 0;  uart_rx_rd   <= 0;
            uart_div_we  <= 0;  uart_div_di  <= 0;
            tx_busy      <= 0;  tx_countdown <= 0;
            uart_tx_data <= 0;
            sdspi_tx_data  <= 8'hFF;  sdspi_clkdiv   <= 16'd199;
            sdspi_start    <= 0;      sdspi_cs_n_reg <= 1'b1;
        end else begin
            // ---- Defaults: clear single-cycle pulses ----
            out_byte_en <= 0;
            uart_we     <= 0;
            uart_rx_rd  <= 0;
            uart_div_we <= 0;
            sdspi_start <= 0;

            // UART TX busy countdown
            if (tx_busy) begin
                if (tx_countdown != 0) tx_countdown <= tx_countdown - 1;
                else                   tx_busy      <= 0;
            end

            // ---- APB WRITE ----
            if (apb_wr) begin
                // GPIO / UART (0x1000_xxxx)
                if (psel_uart) begin
                    case (apb_paddr[4:0])
                        5'h00: begin out_byte_en<=1; out_byte<=apb_pwdata[7:0]; end
                        5'h04: begin
                            if (!tx_busy) begin
                                uart_tx_data <= apb_pwdata[7:0];
                                uart_we      <= 1;
                                tx_busy      <= 1;
                                tx_countdown <= UART_TX_HOLDOFF;
                            end
                        end
                        5'h10: begin
                            uart_div_we <= 4'hF;
                            uart_div_di <= apb_pwdata;
                        end
                        default: ;
                    endcase
                end

                // SD SPI (0x6000_xxxx)
                if (psel_sdspi) begin
                    case (apb_paddr[3:0])
                        4'h0: begin
                            if (!sdspi_busy) begin
                                sdspi_tx_data <= apb_pwdata[7:0];
                                sdspi_start   <= 1;
                            end
                        end
                        4'h8: sdspi_cs_n_reg <= apb_pwdata[0];
                        4'hC: sdspi_clkdiv   <= apb_pwdata[15:0];
                        default: ;
                    endcase
                end

                // AEAD (0x3000_xxxx) — handled entirely inside aead_mmap_wrapper
            end // apb_wr

            // ---- APB READ side-effects ----
            if (apb_rd) begin
                if (psel_uart && apb_paddr[4:0] == 5'h08)
                    uart_rx_rd <= 1;
            end
        end
    end

endmodule

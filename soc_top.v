//==============================================================================
// soc_top.v
// TinyRISC-TinyML -- top-level SoC: PicoRV32 + program RAM + TinyML
// accelerator + UART, wired together through PicoRV32's native memory
// interface with a simple address-decoded bus.
//
// Address map (frozen design decision -- matches software/include/
// accelerator_driver.h and uart.h EXACTLY; if either changes, both must
// change together):
//   0x00000000 - 0x00007FFF : program_ram (32 KiB, program + data)
//   0x02000000 - 0x0200001B : tinyml_accelerator_top (7 registers)
//   0x03000000 - 0x03000007 : simpleuart (CLKDIV @ +0x00, DATA @ +0x04)
//   0x04000000              : LED register (bits [3:0]; write-only from
//                              firmware's point of view, though reads
//                              return the last written value) -- NOT yet
//                              driven by main.c; added so AC-05 (LEDs
//                              reflect RESULT) has somewhere to connect
//                              to. See the note at the bottom of this file.
//   anything else            : returns 32'hDEADBEEF after 1 cycle, rather
//                              than hanging mem_ready forever -- makes an
//                              out-of-range firmware bug visibly wrong
//                              instead of silently freezing the CPU.
//
// Bus timing (see PHASE6 integration notes / conversation record for the
// full reasoning, verified against picorv32.v's actual mem_state logic
// rather than assumed):
//   - program_ram: registered, 1 wait state (PicoRV32's own proven
//     testbench_ez.v pattern -- the safest choice for the module holding
//     the whole program)
//   - tinyml_accelerator_top: combinational, 0 wait states -- matches
//     accelerator_registers.v's actual behavior and everything already
//     verified in Phase 4 (accelerator_registers_tb.v, accelerator_top_tb.v
//     both read reg_rdata combinationally, no clock edge)
//   - simpleuart: variable wait, using its own reg_dat_wait signal --
//     matches picosoc.v's proven integration of this exact module
//
// CPU configuration: default PicoRV32 parameters (ENABLE_MUL=0, no
// interrupts used -- irq tied to 0, per the frozen "no interrupts"
// design decision). PROGADDR_RESET defaults to 0x00000000, matching
// program_ram's base address, so no override is needed.
//==============================================================================
`timescale 1ns / 1ps

module soc_top #(
    parameter FIRMWARE_HEX_FILE = "firmware_sw.hex"
) (
    input  wire clk,
    input  wire resetn,   // active-low, matches PicoRV32's native convention

    output wire uart_tx,
    input  wire uart_rx,

    output wire [3:0] led
);

    // ---- shared PicoRV32 native memory bus ----
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    picorv32 #(
        .PROGADDR_RESET (32'h0000_0000)
    ) u_cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (),

        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),

        // PCPI unused (ENABLE_PCPI=0 default) -- tie inputs off
        .pcpi_wr    (1'b0),
        .pcpi_rd    (32'd0),
        .pcpi_wait  (1'b0),
        .pcpi_ready (1'b0),

        // No interrupts anywhere in this design (frozen decision)
        .irq (32'd0),
        .eoi ()
    );

    // ---- address decode ----
    wire ram_sel   = (mem_addr[31:24] == 8'h00);
    wire accel_sel = (mem_addr[31:24] == 8'h02);
    wire uart_sel  = (mem_addr[31:24] == 8'h03);
    wire led_sel   = (mem_addr[31:24] == 8'h04);
    wire unmapped_sel = !(ram_sel || accel_sel || uart_sel || led_sel);

    // ---- program_ram (registered, 1 wait state) ----
    wire        ram_mem_ready;
    wire [31:0] ram_mem_rdata;

    program_ram #(
        .FIRMWARE_HEX_FILE (FIRMWARE_HEX_FILE),
        .RAM_WORDS         (8192)
    ) u_ram (
        .clk       (clk),
        .mem_valid (mem_valid && ram_sel),
        .mem_wstrb (mem_wstrb),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_ready (ram_mem_ready),
        .mem_rdata (ram_mem_rdata)
    );

    // ---- tinyml_accelerator_top (combinational, 0 wait states) ----
    wire accel_bus_ren = mem_valid && accel_sel && (mem_wstrb == 4'b0000);
    wire accel_bus_wen = mem_valid && accel_sel && (mem_wstrb != 4'b0000);
    wire [31:0] accel_rdata;
    wire accel_mem_ready = mem_valid && accel_sel;

    tinyml_accelerator_top u_accel (
        .clk       (clk),
        .rst       (!resetn),
        .reg_addr  (mem_addr[4:0]),
        .reg_wdata (mem_wdata),
        .reg_wen   (accel_bus_wen),
        .reg_ren   (accel_bus_ren),
        .reg_rdata (accel_rdata)
    );

    // ---- simpleuart (variable wait via reg_dat_wait) ----
    wire uart_dat_sel = uart_sel && (mem_addr[3:0] == 4'h4);
    wire uart_div_sel = uart_sel && (mem_addr[3:0] == 4'h0);

    wire        uart_reg_dat_we = mem_valid && uart_dat_sel && (mem_wstrb != 4'b0000);
    wire        uart_reg_dat_re = mem_valid && uart_dat_sel && (mem_wstrb == 4'b0000);
    wire [3:0]  uart_reg_div_we = (mem_valid && uart_div_sel && (mem_wstrb != 4'b0000)) ? mem_wstrb : 4'b0000;
    wire [31:0] uart_reg_div_do;
    wire [31:0] uart_reg_dat_do;
    wire        uart_reg_dat_wait;

    simpleuart u_uart (
        .clk          (clk),
        .resetn       (resetn),
        .ser_tx       (uart_tx),
        .ser_rx       (uart_rx),
        .reg_div_we   (uart_reg_div_we),
        .reg_div_di   (mem_wdata),
        .reg_div_do   (uart_reg_div_do),
        .reg_dat_we   (uart_reg_dat_we),
        .reg_dat_re   (uart_reg_dat_re),
        .reg_dat_di   (mem_wdata),
        .reg_dat_do   (uart_reg_dat_do),
        .reg_dat_wait (uart_reg_dat_wait)
    );

    wire [31:0] uart_rdata_mux = uart_dat_sel ? uart_reg_dat_do : uart_reg_div_do;
    wire        uart_mem_ready = mem_valid && uart_sel && !uart_reg_dat_wait;

    // ---- LED register (combinational, 0 wait states) ----
    reg [3:0] led_q;
    wire led_wen = mem_valid && led_sel && (mem_wstrb != 4'b0000);
    wire led_mem_ready = mem_valid && led_sel;

    always @(posedge clk) begin
        if (!resetn)
            led_q <= 4'b0000;
        else if (led_wen)
            led_q <= mem_wdata[3:0];
    end

    assign led = led_q;

    // ---- unmapped region: bounded wait, debug sentinel readback ----
    reg unmapped_ready_q;
    always @(posedge clk) begin
        unmapped_ready_q <= 1'b0;
        if (mem_valid && unmapped_sel && !unmapped_ready_q)
            unmapped_ready_q <= 1'b1;
    end

    // ---- final bus mux ----
    assign mem_ready = ram_sel   ? ram_mem_ready   :
                        accel_sel ? accel_mem_ready :
                        uart_sel  ? uart_mem_ready   :
                        led_sel   ? led_mem_ready    :
                        unmapped_ready_q;

    assign mem_rdata = ram_sel   ? ram_mem_rdata          :
                        accel_sel ? accel_rdata            :
                        uart_sel  ? uart_rdata_mux          :
                        led_sel   ? {28'd0, led_q}          :
                        32'hDEADBEEF;

endmodule

//==============================================================================
// NOTE on the LED register and AC-05:
// main.c (Phase 5) does not currently write to 0x04000000 -- this register
// exists in hardware but nothing drives it yet. To actually satisfy AC-05
// ("LEDs correctly reflect RESULT"), add one line to main.c's per-vector
// loop: a plain volatile store of the prediction bit to 0x04000000, the
// same pattern as accel_write()/uart_write_reg(). This is deliberately
// left as a small, explicit follow-up rather than silently added here,
// since it touches a file already delivered and tested in Phase 5.
//==============================================================================

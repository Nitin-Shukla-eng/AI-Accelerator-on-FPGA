//==============================================================================
// soc_top_tb.v
// Full end-to-end integration testbench for rtl/top/soc_top.v.
// HDS Chapter 10 / VIS integration-test matrix, final integration level:
// runs the ACTUAL COMPILED FIRMWARE (firmware_sw.hex / firmware_hw.hex)
// on the ACTUAL PicoRV32 core, driving the ACTUAL accelerator RTL through
// the ACTUAL address-decoded bus, and verifies the result over a
// bit-level-accurate simulated UART receiver -- this is the first test in
// the whole project that doesn't assume anything about the CPU/bus/
// firmware chain; it just runs the real system and listens to what comes
// out the wire, exactly as a real terminal would in Phase 8.
//
// Both firmware images (Version 1 and Version 2) run SIMULTANEOUSLY on
// two separate soc_top instances sharing one clock -- this is not a
// performance shortcut, it's simply how two independently-reset SoCs
// running concurrently in one timeline naturally behaves in an
// event-driven simulator; splitting it into two sequential runs would
// not be meaningfully faster.
//
// IMPORTANT -- simulation time: this uses REAL UART bit timing (the
// clkdiv value main.c actually computed at compile time, read directly
// from each DUT's own simpleuart instance rather than assumed here), so
// this simulation genuinely takes as many clock cycles as the real
// hardware would. Expect this to take noticeably longer to run than any
// other testbench in this project (potentially several minutes of
// wall-clock time in Icarus) -- that's expected, not a hang. A bounded
// timeout (CYCLE_TIMEOUT below) prevents a genuine hang from running
// forever.
//
// Run (single line -- paths below assume firmware_sw.hex/firmware_hw.hex
// have been copied into this same directory; adjust FIRMWARE_HEX_FILE
// parameters below, or copy the files, if you'd rather keep them in
// software/):
//   iverilog -o soc_top_tb.vvp soc_top_tb.v ../../rtl/top/soc_top.v ../../rtl/cpu/picorv32.v ../../rtl/uart/simpleuart.v ../../rtl/memory/program_ram.v ../../rtl/top/tinyml_accelerator_top.v ../../rtl/accelerator/accelerator_registers.v ../../rtl/accelerator/controller_fsm.v ../../rtl/accelerator/hidden_layer.v ../../rtl/accelerator/output_layer.v ../../rtl/accelerator/prediction_register.v ../../rtl/math/mac.v ../../rtl/math/relu.v ../../rtl/memory/hidden_weight_rom.v ../../rtl/memory/hidden_bias_rom.v ../../rtl/memory/output_weight_rom.v ../../rtl/memory/output_bias_rom.v
//   vvp soc_top_tb.vvp
//==============================================================================
`timescale 1ns / 1ps

module soc_top_tb;

    localparam [8*17-1:0] SENTINEL_PASS = "ALL VECTORS MATCH";
    localparam CYCLE_TIMEOUT = 50_000_000;

    reg clk;
    reg resetn;

    wire uart_tx_sw, uart_tx_hw;
    wire [3:0] led_sw, led_hw;

    initial clk = 1'b0;
    always #10 clk = ~clk; // 20ns period = 50MHz, matching main.c's SYSTEM_CLOCK_HZ assumption

    // ---- Version 1 (software) DUT ----
    soc_top #(
        .FIRMWARE_HEX_FILE ("firmware_sw.hex")
    ) dut_sw (
        .clk     (clk),
        .resetn  (resetn),
        .uart_tx (uart_tx_sw),
        .uart_rx (1'b1), // idle-high, unused (no RX test data sent)
        .led     (led_sw)
    );

    // ---- Version 2 (hardware accelerator) DUT ----
    soc_top #(
        .FIRMWARE_HEX_FILE ("firmware_hw.hex")
    ) dut_hw (
        .clk     (clk),
        .resetn  (resetn),
        .uart_tx (uart_tx_hw),
        .uart_rx (1'b1),
        .led     (led_hw)
    );

    initial begin
        resetn = 1'b0;
        repeat (20) @(posedge clk);
        resetn = 1'b1;
    end

    // =========================================================
    // UART receiver -- Version 1 (software)
    // =========================================================
    reg sw_pass;
    reg sw_finished;
    reg [8*17-1:0] sw_window;
    integer sw_bit_period;
    integer sw_bit_idx;
    reg [7:0] sw_rx_byte;
    integer sw_byte_count;

    initial begin
        sw_pass = 1'b0;
        sw_finished = 1'b0;
        sw_window = {(8*17){1'b0}};
        sw_byte_count = 0;

        @(posedge resetn);

        forever begin
            @(negedge uart_tx_sw);
            sw_bit_period = dut_sw.u_uart.cfg_divider + 1;

            repeat (sw_bit_period / 2) @(posedge clk); // align to mid-bit
            for (sw_bit_idx = 0; sw_bit_idx < 8; sw_bit_idx = sw_bit_idx + 1) begin
                repeat (sw_bit_period) @(posedge clk);
                sw_rx_byte[sw_bit_idx] = uart_tx_sw;
            end
            repeat (sw_bit_period) @(posedge clk); // stop bit, not checked

            sw_byte_count = sw_byte_count + 1;
            sw_window = {sw_window[8*16-1:0], sw_rx_byte};

            if (sw_window == SENTINEL_PASS) begin
                sw_pass = 1'b1;
                sw_finished = 1'b1;
            end
        end
    end

    // =========================================================
    // UART receiver -- Version 2 (hardware accelerator)
    // =========================================================
    reg hw_pass;
    reg hw_finished;
    reg [8*17-1:0] hw_window;
    integer hw_bit_period;
    integer hw_bit_idx;
    reg [7:0] hw_rx_byte;
    integer hw_byte_count;

    initial begin
        hw_pass = 1'b0;
        hw_finished = 1'b0;
        hw_window = {(8*17){1'b0}};
        hw_byte_count = 0;

        @(posedge resetn);

        forever begin
            @(negedge uart_tx_hw);
            hw_bit_period = dut_hw.u_uart.cfg_divider + 1;

            repeat (hw_bit_period / 2) @(posedge clk);
            for (hw_bit_idx = 0; hw_bit_idx < 8; hw_bit_idx = hw_bit_idx + 1) begin
                repeat (hw_bit_period) @(posedge clk);
                hw_rx_byte[hw_bit_idx] = uart_tx_hw;
            end
            repeat (hw_bit_period) @(posedge clk);

            hw_byte_count = hw_byte_count + 1;
            hw_window = {hw_window[8*16-1:0], hw_rx_byte};

            if (hw_window == SENTINEL_PASS) begin
                hw_pass = 1'b1;
                hw_finished = 1'b1;
            end
        end
    end

    // =========================================================
    // Overall timeout / completion watchdog
    // =========================================================
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    initial begin
        wait ((sw_finished && hw_finished) || cycle_count > CYCLE_TIMEOUT);

        $display("====================================================");
        if (cycle_count > CYCLE_TIMEOUT && !(sw_finished && hw_finished)) begin
            $display("soc_top_tb: TIMEOUT after %0d cycles", CYCLE_TIMEOUT);
            $display("  Version 1 (software)   : finished=%0d pass=%0d bytes_received=%0d",
                      sw_finished, sw_pass, sw_byte_count);
            $display("  Version 2 (hardware)   : finished=%0d pass=%0d bytes_received=%0d",
                      hw_finished, hw_pass, hw_byte_count);
            $display("soc_top_tb: FAILURES PRESENT (timeout)");
        end else if (sw_pass && hw_pass) begin
            $display("Version 1 (software)   : PASS (\"ALL VECTORS MATCH\" received, %0d bytes total)", sw_byte_count);
            $display("Version 2 (hardware)   : PASS (\"ALL VECTORS MATCH\" received, %0d bytes total)", hw_byte_count);
            $display("soc_top_tb: ALL TESTS PASSED -- both firmware images run correctly");
            $display("  on the real PicoRV32 core, through the real address-decoded bus,");
            $display("  against the real accelerator RTL, verified over a real simulated UART.");
        end else begin
            $display("Version 1 (software)   : finished=%0d pass=%0d", sw_finished, sw_pass);
            $display("Version 2 (hardware)   : finished=%0d pass=%0d", hw_finished, hw_pass);
            $display("soc_top_tb: FAILURES PRESENT");
        end
        $display("====================================================");

        $finish;
    end

endmodule

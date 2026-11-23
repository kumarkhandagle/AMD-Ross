
`timescale 1ns / 1ps

module tb_spi_dac;

    // 125 MHz system clock
    reg sys_clk = 1'b0;
    always #4 sys_clk = ~sys_clk;

    reg         rst_n   = 1'b0;
    reg         start   = 1'b0;
    reg  [11:0] dac_in1 = 12'h000;

    wire mosi1, sclk, cs_n, done;

    integer errors = 0;
    time t_first_rise;

    spi_dac dut (
        .sys_clk (sys_clk),
        .rst_n   (rst_n),
        .dac_in1 (dac_in1),
        .start   (start),
        .mosi1   (mosi1),
        .sclk    (sclk),
        .cs_n    (cs_n),
        .done    (done)
    );

    task run_transfer;
        input [11:0] data;
        reg [15:0] received;
        reg [15:0] expected;
        integer bit_index;
        begin
            received = 16'h0000;
            expected = {4'b0000, data};

            // Start a new transaction
            @(negedge sclk);
            dac_in1 = data;
            start   = 1'b1;

            wait (cs_n === 1'b0);
            start = 1'b0;

            // Capture 16 bits, MSB first
            for (bit_index = 15; bit_index >= 0;
                 bit_index = bit_index - 1) begin

                @(negedge sclk);
                #1;
                received[bit_index] = mosi1;

                if (cs_n !== 1'b0 || done !== 1'b0) begin
                    $display("FAIL: CS/done during bit %0d",
                             bit_index);
                    errors = errors + 1;
                end
            end

            // Check transaction completion
            @(posedge sclk);
            #1;
            if (cs_n !== 1'b1 || done !== 1'b1) begin
                $display("FAIL: Missing completion");
                errors = errors + 1;
            end

            // Compare transmitted data
            if (received !== expected) begin
                $display("FAIL: expected=%h actual=%h",
                         expected, received);
                errors = errors + 1;
            end else begin
                $display("PASS: data=%h received=%h",
                         data, received);
            end

            // Check return to idle
            @(posedge sclk);
            #1;
            if (cs_n !== 1'b1 || done !== 1'b0) begin
                $display("FAIL: Idle recovery");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Reset test
        repeat (6) @(negedge sys_clk);
        #1;

        if (sclk !== 1'b0 ||
            cs_n !== 1'b1 ||
            done !== 1'b0) begin
            $display("FAIL: Reset");
            errors = errors + 1;
        end

        rst_n = 1'b1;

        // Clock divider test
        @(posedge sclk);
        t_first_rise = $time;
        @(posedge sclk);

        if (($time - t_first_rise) != 80) begin
            $display("FAIL: Incorrect SPI clock period");
            errors = errors + 1;
        end

        if (cs_n !== 1'b1 || done !== 1'b0) begin
            $display("FAIL: Initial idle");
            errors = errors + 1;
        end

        // SPI smoke tests
        run_transfer(12'hA5C);
        run_transfer(12'hFFF);

        if (errors == 0)
            $display("SMOKE TEST PASS");
        else
            $fatal(1, "SMOKE TEST FAIL: %0d errors", errors);

        $finish;
    end

    // Simulation watchdog
    initial begin
        #25000;
        $fatal(1, "SMOKE TEST TIMEOUT");
    end

endmodule

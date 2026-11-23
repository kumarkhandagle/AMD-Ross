`timescale 1ns/1ps

// Protected, self-checking AXI4-Lite master testbench.
// Vivado behavioral simulation: compile this file together with axilite_m.v.
// Coverage = observed functional scenarios (not percentage of passing tests).
module axilite_m_tb;

  localparam integer NUM_TESTS = 15;
  localparam integer CLK_PERIOD = 10;

  reg         m_axi_aclk = 1'b0;
  reg         m_axi_aresetn = 1'b0;
  always #(CLK_PERIOD/2) m_axi_aclk = ~m_axi_aclk;

  reg         new_tx = 1'b0;
  reg         wr = 1'b0;
  reg  [31:0] waddr = 32'd0;
  reg  [31:0] raddr = 32'd0;
  reg  [31:0] din   = 32'd0;
  wire [31:0] dout;
  wire [1:0]  resp;
  wire        wr_timeout, rd_timeout;

  wire        m_axi_awvalid;
  reg         m_axi_awready = 1'b0;
  wire [31:0] m_axi_awaddr;
  wire        m_axi_wvalid;
  reg         m_axi_wready = 1'b0;
  wire [31:0] m_axi_wdata;
  wire [3:0]  m_axi_wstrb;
  reg         m_axi_bvalid = 1'b0;
  wire        m_axi_bready;
  reg  [1:0]  m_axi_bresp = 2'b00;
  wire        m_axi_arvalid;
  reg         m_axi_arready = 1'b0;
  wire [31:0] m_axi_araddr;
  reg         m_axi_rvalid = 1'b0;
  wire        m_axi_rready;
  reg  [31:0] m_axi_rdata = 32'd0;
  reg  [1:0]  m_axi_rresp = 2'b00;

  axilite_m dut (
    .new_tx(new_tx), .wr(wr), .waddr(waddr), .raddr(raddr), .din(din),
    .dout(dout), .resp(resp),
    .wr_timeout(wr_timeout), .rd_timeout(rd_timeout),
    .m_axi_aclk(m_axi_aclk), .m_axi_aresetn(m_axi_aresetn),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp)
  );

  // Slave configuration. Delay values count falling edges since test setup;
  // a ready signal remains asserted, as a real slave may do.
  bit slave_active = 0;
  bit enable_aw = 0, enable_w = 0, enable_b = 0;
  bit enable_ar = 0, enable_r = 0;
  bit release_r_after_handshake = 0;
  bit check_stability = 1;
  integer aw_delay = 0, w_delay = 0, b_delay = 0;
  integer ar_delay = 0, r_delay = 0;
  integer slave_cycle = 0, b_wait = 0, r_wait = 0;
  reg [31:0] expected_address = 0;
  reg [31:0] expected_wdata   = 0;
  reg [31:0] slave_rdata     = 0;
  reg [1:0]  slave_rresp     = 0;

  // Per-test observations / checker state.
  integer aw_hs = 0, w_hs = 0, b_hs = 0, ar_hs = 0, r_hs = 0;
  integer protocol_errors = 0;
  integer r_wait_cycles = 0;
  bit aw_stall_seen = 0, w_stall_seen = 0, ar_stall_seen = 0;
  bit w_first_seen = 0, wr_timeout_seen = 0, rd_timeout_seen = 0;
  bit prev_aw_stalled = 0, prev_w_stalled = 0, prev_ar_stalled = 0;
  reg [31:0] prev_awaddr = 0, prev_wdata = 0, prev_araddr = 0;
  reg [3:0]  prev_wstrb = 0;

  integer tests_passed = 0, tests_failed = 0;
  reg [NUM_TESTS-1:0] coverage_bins = '0;

  // Minimal, deterministic AXI4-Lite slave response model.
  // All inputs change on falling edges; DUT samples them on rising edges.
  always @(negedge m_axi_aclk) begin
    if (!m_axi_aresetn || !slave_active) begin
      m_axi_awready = 0;
      m_axi_wready  = 0;
      m_axi_bvalid  = 0;
      m_axi_bresp   = 0;
      m_axi_arready = 0;
      m_axi_rvalid  = 0;
      m_axi_rdata   = 0;
      m_axi_rresp   = 0;
    end else begin
      slave_cycle = slave_cycle + 1;
      m_axi_awready = enable_aw && (slave_cycle >= aw_delay);
      m_axi_wready  = enable_w  && (slave_cycle >= w_delay);
      m_axi_arready = enable_ar && (slave_cycle >= ar_delay);

      // BVALID is legal only after BOTH write address and data were accepted.
      m_axi_bvalid = 0;
      if (enable_b && aw_hs > 0 && w_hs > 0 && b_hs == 0) begin
        if (b_wait >= b_delay)
          m_axi_bvalid = 1;
        else
          b_wait = b_wait + 1;
      end
      m_axi_bresp = 2'b00;

      // RVALID is legal after a read address was accepted,
      // or simultaneously with read address handshake for zero-wait read corner case.
      m_axi_rvalid = 0;
      if (enable_r && (ar_hs > 0 || (m_axi_arready && m_axi_arvalid)) && r_hs == 0) begin
        if (r_wait >= r_delay)
          m_axi_rvalid = 1;
        else
          r_wait = r_wait + 1;
      end
      // Once RVALID/RREADY have handshaken, the slave may change RDATA/RRESP.
      if (release_r_after_handshake && r_hs > 0) begin
        m_axi_rdata = 32'h0000_0000;
        m_axi_rresp = 2'b00;
      end else begin
        m_axi_rdata = slave_rdata;
        m_axi_rresp = slave_rresp;
      end
    end
  end

  // Independent bus monitor, including VALID/payload stability under stall.
  always @(posedge m_axi_aclk) begin
    if (m_axi_aresetn && slave_active) begin
      if (wr_timeout === 1'b1) wr_timeout_seen = 1;
      if (rd_timeout === 1'b1) rd_timeout_seen = 1;

      if (check_stability) begin
        if (prev_aw_stalled &&
            (m_axi_awvalid !== 1'b1 || m_axi_awaddr !== prev_awaddr))
          protocol_errors = protocol_errors + 1;
        if (prev_w_stalled &&
            (m_axi_wvalid !== 1'b1 || m_axi_wdata !== prev_wdata ||
             m_axi_wstrb !== prev_wstrb))
          protocol_errors = protocol_errors + 1;
        if (prev_ar_stalled &&
            (m_axi_arvalid !== 1'b1 || m_axi_araddr !== prev_araddr))
          protocol_errors = protocol_errors + 1;
      end

      if (m_axi_awvalid && !m_axi_awready) aw_stall_seen = 1;
      if (m_axi_wvalid  && !m_axi_wready)  w_stall_seen = 1;
      if (m_axi_arvalid && !m_axi_arready) ar_stall_seen = 1;
      if (ar_hs > 0 && r_hs == 0 && !m_axi_rvalid)
        r_wait_cycles = r_wait_cycles + 1;

      // A W handshake before any AW handshake is an intentional coverage bin.
      if (m_axi_wvalid && m_axi_wready && aw_hs == 0 &&
          !(m_axi_awvalid && m_axi_awready))
        w_first_seen = 1;

      if (m_axi_awvalid && m_axi_awready) begin
        aw_hs = aw_hs + 1;
        if (m_axi_awaddr !== expected_address)
          protocol_errors = protocol_errors + 1;
      end
      if (m_axi_wvalid && m_axi_wready) begin
        w_hs = w_hs + 1;
        if (m_axi_wdata !== expected_wdata || m_axi_wstrb !== 4'hF)
          protocol_errors = protocol_errors + 1;
      end
      if (m_axi_bvalid && m_axi_bready)
        b_hs = b_hs + 1;
      if (m_axi_arvalid && m_axi_arready) begin
        ar_hs = ar_hs + 1;
        if (m_axi_araddr !== expected_address)
          protocol_errors = protocol_errors + 1;
      end
      if (m_axi_rvalid && m_axi_rready)
        r_hs = r_hs + 1;

      prev_aw_stalled = m_axi_awvalid && !m_axi_awready;
      prev_w_stalled  = m_axi_wvalid  && !m_axi_wready;
      prev_ar_stalled = m_axi_arvalid && !m_axi_arready;
      prev_awaddr = m_axi_awaddr;
      prev_wdata  = m_axi_wdata;
      prev_wstrb  = m_axi_wstrb;
      prev_araddr = m_axi_araddr;
    end
  end

  task automatic reset_observations;
    begin
      aw_hs=0; w_hs=0; b_hs=0; ar_hs=0; r_hs=0;
      protocol_errors=0; r_wait_cycles=0;
      aw_stall_seen=0; w_stall_seen=0; ar_stall_seen=0;
      w_first_seen=0; wr_timeout_seen=0; rd_timeout_seen=0;
      prev_aw_stalled=0; prev_w_stalled=0; prev_ar_stalled=0;
      prev_awaddr=0; prev_wdata=0; prev_wstrb=0; prev_araddr=0;
      slave_cycle=0; b_wait=0; r_wait=0;
    end
  endtask

  task automatic configure_write(
      input bit aw_on, input bit w_on, input bit b_on,
      input integer aw_dly, input integer w_dly, input integer b_dly,
      input reg [31:0] address, input reg [31:0] data);
    begin
      @(posedge m_axi_aclk); #1;
      slave_active = 0;
      reset_observations();
      enable_aw=aw_on; enable_w=w_on; enable_b=b_on;
      enable_ar=0; enable_r=0;
      aw_delay=aw_dly; w_delay=w_dly; b_delay=b_dly;
      ar_delay=0; r_delay=0;
      release_r_after_handshake=0;
      // A deliberate timeout can abandon VALID; assess timeout separately.
      check_stability = aw_on && w_on;
      expected_address=address; expected_wdata=data;
      slave_active = 1;
    end
  endtask

  task automatic configure_read(
      input bit ar_on, input bit r_on,
      input integer ar_dly, input integer r_dly,
      input bit release_data,
      input reg [31:0] address, input reg [31:0] data,
      input reg [1:0] read_response);
    begin
      @(posedge m_axi_aclk); #1;
      slave_active = 0;
      reset_observations();
      enable_aw=0; enable_w=0; enable_b=0;
      enable_ar=ar_on; enable_r=r_on;
      aw_delay=0; w_delay=0; b_delay=0;
      ar_delay=ar_dly; r_delay=r_dly;
      release_r_after_handshake=release_data;
      check_stability=ar_on;
      expected_address=address;
      slave_rdata=data; slave_rresp=read_response;
      slave_active = 1;
    end
  endtask

  task automatic launch_write(input reg [31:0] address,
                               input reg [31:0] data);
    begin
      @(negedge m_axi_aclk);
      waddr=address; din=data; wr=1; new_tx=1;
      @(negedge m_axi_aclk);
      new_tx=0;
    end
  endtask

  task automatic launch_read(input reg [31:0] address);
    begin
      @(negedge m_axi_aclk);
      raddr=address; wr=0; new_tx=1;
      @(negedge m_axi_aclk);
      new_tx=0;
    end
  endtask

  task automatic tick(input integer n);
    begin
      repeat (n) @(posedge m_axi_aclk);
      #1;
    end
  endtask

  task automatic pulse_reset;
    begin
      @(negedge m_axi_aclk);
      m_axi_aresetn = 0;
      tick(3);
      @(negedge m_axi_aclk);
      m_axi_aresetn = 1;
      tick(2);
    end
  endtask

  task automatic record_test(input integer id, input string description,
                             input bit passed, input bit covered);
    begin
      if (covered) coverage_bins[id-1] = 1'b1;
      if (passed) begin
        tests_passed = tests_passed + 1;
        $display("ST_%02d: PASS (%s)", id, description);
      end else begin
        tests_failed = tests_failed + 1;
        $display("ST_%02d: FAIL (%s)", id, description);
        $display("FAILED_TEST: ST_%02d", id);
        $display("  AW=%0d W=%0d B=%0d AR=%0d R=%0d ERR=%0d WR_TO=%0d RD_TO=%0d",
          aw_hs, w_hs, b_hs, ar_hs, r_hs, protocol_errors,
          wr_timeout_seen, rd_timeout_seen);
      end
    end
  endtask

  task automatic do_write_test(
      input integer id, input string description,
      input bit aw_on, input bit w_on, input bit b_on,
      input integer aw_dly, input integer w_dly, input integer b_dly);
    reg [31:0] address, data;
    bit expected_timeout, passed, covered;
    begin
      address=32'h4000_0000 + id*4;
      data=32'hA500_0000 | id;
      configure_write(aw_on,w_on,b_on,aw_dly,w_dly,b_dly,address,data);
      launch_write(address,data);
      tick(48); // Enough for the RTL's 4-bit timeout counters.
      expected_timeout = !(aw_on && w_on && b_on);
      passed = (aw_hs == (aw_on ? 1 : 0)) &&
               (w_hs == (w_on ? 1 : 0)) &&
               (b_hs == (b_on ? 1 : 0)) &&
               (wr_timeout_seen == expected_timeout) &&
               (rd_timeout_seen == 0) && (protocol_errors == 0);
      case (id)
        1: covered = (aw_hs>0 && w_hs>0 && b_hs>0);
        2: covered = (aw_stall_seen && aw_hs>0 && b_hs>0);
        3: covered = (w_stall_seen && w_hs>0 && b_hs>0);
        4: covered = w_first_seen;
        5: covered = (wr_timeout_seen && aw_hs==0);
        6: covered = (wr_timeout_seen && aw_hs>0 && w_hs==0);
        7: covered = (wr_timeout_seen && aw_hs>0 && w_hs>0 && b_hs==0);
        15: covered = (wr_timeout_seen && aw_hs==0 && w_hs>0);
        default: covered = 0;
      endcase
      record_test(id,description,passed,covered);
    end
  endtask

  task automatic do_read_test(
      input integer id, input string description,
      input bit ar_on, input bit r_on,
      input integer ar_dly, input integer r_dly,
      input reg [1:0] r_response, input bit release_data);
    reg [31:0] address, data, captured_dout;
    reg [1:0] captured_resp;
    integer i;
    bit expected_timeout, passed, covered;
    begin
      address=32'h5000_0000 + id*4;
      data=32'hC0DE_0000 | id;
      configure_read(ar_on,r_on,ar_dly,r_dly,release_data,
                     address,data,r_response);
      launch_read(address);
      captured_dout = 32'hDEAD_BEEF;
      captured_resp = 2'b11;

      // A bounded wait ensures a broken DUT cannot hang the regression.
      for (i=0; i<42 && r_hs==0; i=i+1) begin
        @(posedge m_axi_aclk); #1;
      end
      if (r_hs > 0) begin
        // The slave deasserts RVALID (and optionally changes RDATA) at
        // the following falling edge. Check data while DUT is in its
        // completion state, before the next rising edge clears outputs.
        @(negedge m_axi_aclk); #1;
        captured_dout=dout;
        captured_resp=resp;
      end
      tick(10);

      expected_timeout = !(ar_on && r_on);
      passed = (ar_hs == (ar_on ? 1 : 0)) &&
               (r_hs == ((ar_on && r_on) ? 1 : 0)) &&
               (rd_timeout_seen == expected_timeout) &&
               (wr_timeout_seen == 0) && (protocol_errors == 0);
      if (!expected_timeout)
        passed = passed && (captured_dout === data) &&
                            (captured_resp === r_response);
      case (id)
        8:  covered = (ar_hs>0 && r_hs>0);
        9:  covered = (ar_stall_seen && ar_hs>0 && r_hs>0);
        10: covered = (r_wait_cycles>=3 && r_hs>0);
        11: covered = (r_hs>0 && r_response!=0);
        12: covered = (rd_timeout_seen && ar_hs==0);
        13: covered = (rd_timeout_seen && ar_hs>0 && r_hs==0);
        14: covered = (release_r_after_handshake && r_hs>0);
        default: covered = 0;
      endcase
      record_test(id,description,passed,covered);
      if (!passed && !expected_timeout)
        $display("  READ expected data=%h resp=%b, actual data=%h resp=%b",
                 data,r_response,captured_dout,captured_resp);
    end
  endtask

  function integer count_coverage;
    integer i;
    begin
      count_coverage=0;
      for (i=0; i<NUM_TESTS; i=i+1)
        if (coverage_bins[i]) count_coverage=count_coverage+1;
    end
  endfunction

  integer cov_count;
  initial begin
    new_tx=0; wr=0;
    m_axi_aresetn=0;
    tick(5);
    @(negedge m_axi_aclk);
    m_axi_aresetn=1;
    tick(3);

    do_write_test( 1,"write: zero-wait response",      1,1,1,0,0,0);
    do_write_test( 2,"write: AW channel stalled",     1,1,1,6,6,0);
    do_write_test( 3,"write: W channel stalled",      1,1,1,0,7,0);
    do_write_test( 4,"write: W accepted before AW",   1,1,1,7,0,0);
    do_write_test( 5,"write: AW timeout",             0,0,0,0,0,0);
    pulse_reset();
    do_write_test( 6,"write: W timeout after AW",     1,0,0,0,0,0);
    pulse_reset();
    do_write_test( 7,"write: B response timeout",     1,1,0,0,0,0);
    pulse_reset();

    do_read_test ( 8,"read: zero-wait response",       1,1,0,0,2'b00,0);
    do_read_test ( 9,"read: AR channel stalled",       1,1,6,0,2'b00,0);
    do_read_test (10,"read: R channel delayed",       1,1,0,8,2'b00,0);
    do_read_test (11,"read: SLVERR response",         1,1,0,0,2'b10,0);
    do_read_test (12,"read: AR timeout",              0,0,0,0,2'b00,0);
    pulse_reset();
    do_read_test (13,"read: R timeout after AR",      1,0,0,0,2'b00,0);
    pulse_reset();
    do_read_test (14,"read: slave releases RDATA",    1,1,0,0,2'b10,1);
    do_write_test(15,"write: AW timeout after W",     0,1,0,0,0,0);
    pulse_reset();

    cov_count=count_coverage();
    $display("--------------------------------------------------");
    $display("TESTS_PASSED: %0d",tests_passed);
    $display("TESTS_FAILED: %0d",tests_failed);
    $display("COVERAGE: %0d%% (%0d/%0d bins)",
             (cov_count*100)/NUM_TESTS,cov_count,NUM_TESTS);
    for (integer j=0; j<NUM_TESTS; j=j+1)
      if (!coverage_bins[j])
        $display("UNCOVERED_BIN: ST_%02d", j+1);
    if (tests_failed==0 && tests_passed==NUM_TESTS && cov_count==NUM_TESTS) begin
      $display("RESULT: PASS");
      $display("ALL TESTS PASSED");
    end else begin
      $display("RESULT: FAIL");
      $display("SOME TESTS FAILED");
    end
    $finish;
  end

  // Global watchdog: regression must terminate even with a stalled DUT.
  initial begin
    #20000;
    $display("RESULT: FAIL");
    $display("WATCHDOG_TIMEOUT");
    $finish;
  end
endmodule
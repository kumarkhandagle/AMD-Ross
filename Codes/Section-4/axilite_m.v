module axilite_m
(  
  input wire     new_tx,
  input wire     wr,
  input wire  [31:0] waddr,
  input wire  [31:0] raddr,
  input wire  [31:0] din,
  output reg [31:0]  dout,
  output reg [1:0]  resp,
  output reg     wr_timeout, rd_timeout,

  input wire    m_axi_aclk,
  input wire    m_axi_aresetn,
  output reg     m_axi_awvalid,
  input wire     m_axi_awready,
  output reg [31: 0] m_axi_awaddr,

  output reg     m_axi_wvalid,
  input wire     m_axi_wready,
  output reg [31: 0] m_axi_wdata,
  output reg [3: 0] m_axi_wstrb,

  input wire     m_axi_bvalid,
  output reg     m_axi_bready,
  input wire [1: 0] m_axi_bresp,

  output reg     m_axi_arvalid,
  input wire     m_axi_arready,
  output reg [31: 0] m_axi_araddr,

  input wire     m_axi_rvalid,
  output reg     m_axi_rready,
  input wire [31: 0] m_axi_rdata,
  input wire [1: 0] m_axi_rresp
);


/////////////write FSM  

localparam wr_idle            = 0,
           wait_for_wr_op     = 1,
           waddr_write        = 2,
           wait_for_wdata_ack = 3,
           wait_for_waddr_ack = 4,
           wait_for_wr_resp   = 5,
           comp_wr_tx         = 6,
           wr_fault           = 7;
     
reg [2:0] wstate   = wr_idle;
reg [2:0] wnext_state = wr_idle;
reg [3:0] wr_count  = 0;
     
////////////////reset decoding
always @(posedge m_axi_aclk) begin
  if (m_axi_aresetn == 1'b0)
    wstate <= wr_idle;
  else
    wstate <= wnext_state;    
end

/////////////////next state decoder
always @(*) begin
  case (wstate)
    wr_idle: begin
      m_axi_awvalid = 0;
      m_axi_awaddr = 0;
      m_axi_wvalid = 0;
      m_axi_wdata  = 0;
      m_axi_wstrb  = 0;
      m_axi_bready = 0;
      wr_timeout  = 1'b0;
      if(new_tx == 1'b1)
        wnext_state  = wait_for_wr_op;
      else
        wnext_state  = wr_idle;
    end

    wait_for_wr_op: begin
      if (wr == 1)
        wnext_state = waddr_write;
      else
        wnext_state = wr_idle;
    end

    waddr_write: begin
      m_axi_wstrb  = 4'b1111;
      m_axi_awvalid = 1;
      m_axi_wvalid = 1;
      m_axi_awaddr = waddr;
      m_axi_wdata  = din;
      m_axi_bready = 1;
       
      if (m_axi_awready == 1 && m_axi_wready == 1)
        wnext_state = wait_for_wr_resp;
      else if (m_axi_awready == 1)
        wnext_state = wait_for_wdata_ack;
      else if (m_axi_wready == 1)
        wnext_state = wait_for_waddr_ack;
      else if (wr_count == 15)
        wnext_state = wr_fault;
      else
        wnext_state = waddr_write;
    end

    wait_for_wdata_ack: begin
      m_axi_awvalid = 0;
      m_axi_awaddr = 0;
      if (m_axi_wready == 1)
        wnext_state = wait_for_wr_resp;
      else if (wr_count == 14)
        wnext_state = wr_fault;
      else
        wnext_state = wait_for_wdata_ack;  
    end

    wait_for_waddr_ack: begin
      m_axi_wvalid = 0;
      m_axi_wdata  = 0;
      m_axi_wstrb  = 0;
      m_axi_awvalid = 1;
      m_axi_awaddr = waddr;
      m_axi_bready = 1;
      if (m_axi_awready == 1)
        wnext_state = wait_for_wr_resp;
      else if (wr_count == 14)
        wnext_state = wr_fault;
      else
        wnext_state = wait_for_waddr_ack;
    end

    wait_for_wr_resp: begin
      m_axi_awvalid = 0;
      m_axi_wvalid = 0;
      m_axi_wdata  = 0;
      m_axi_awaddr = 0;
      if (m_axi_bvalid == 1)
        wnext_state = comp_wr_tx;
      else if (wr_count == 14)
        wnext_state = wr_fault;
      else
        wnext_state = wait_for_wr_resp;
    end

    comp_wr_tx: begin
      m_axi_bready = 0;
      wnext_state = wr_idle;
    end

    wr_fault: begin
      wr_timeout    = 1'b1;
      if (m_axi_aresetn == 1'b0)
        wnext_state = wr_idle;
      else
        wnext_state = wr_fault;
    end

    default: wnext_state = wr_idle;
  endcase
end

///////write counter
always @(posedge m_axi_aclk) begin
  if (!m_axi_aresetn || wstate == wr_idle || wstate == wait_for_wr_op || wstate != wnext_state)
    wr_count <= 4'd0;
  else
    wr_count <= wr_count + 1'b1;
end



/////////////////read FSM

localparam rd_idle        = 0,
           wait_for_rd_op = 1,
           raddr_write    = 2,
           wait_for_rdata = 3,
           comp_rd_tx     = 4,
           rd_fault       = 5;

reg [2:0] rstate   = rd_idle, rnext_state = rd_idle;
reg [3:0] rd_count  = 0;

always @(posedge m_axi_aclk) begin
  if (m_axi_aresetn == 1'b0)
    rstate <= rd_idle;
  else
    rstate <= rnext_state;
end

//////////
always @(*) begin
  case (rstate)
    rd_idle: begin
      m_axi_arvalid = 0;
      m_axi_araddr = 0;
      m_axi_rready = 0;
      rd_timeout  = 1'b0;
       
      if(new_tx == 1'b1)
        rnext_state  = wait_for_rd_op;
      else
        rnext_state  = rd_idle;
       
    end

    wait_for_rd_op: begin
      if (wr == 0)
        rnext_state = raddr_write;
      else
        rnext_state = rd_idle;
    end

    raddr_write: begin
      m_axi_arvalid = 1;
      m_axi_araddr = raddr;
      m_axi_rready = 1'b1;
       
      if(m_axi_arready == 1 && m_axi_rvalid == 1)
        rnext_state = comp_rd_tx;
      else if (m_axi_arready == 1)
        rnext_state = wait_for_rdata;
      else if (rd_count == 15)
        rnext_state = rd_fault;
      else
        rnext_state = raddr_write;
    end

    wait_for_rdata: begin
      m_axi_arvalid = 0;
      m_axi_araddr = 0;
      m_axi_rready = 1'b1;
      if (m_axi_rvalid == 1)
        rnext_state = comp_rd_tx;
      else if (rd_count == 14)
        rnext_state = rd_fault;
      else
        rnext_state = wait_for_rdata;
    end

    comp_rd_tx: begin
      m_axi_rready = 1'b0;
      m_axi_arvalid = 1'b0;
      rnext_state  = rd_idle;
    end

    rd_fault: begin
      rd_timeout    = 1'b1;
      if (m_axi_aresetn == 1'b0)
        rnext_state = rd_idle;
      else
        rnext_state = rd_fault;
    end

    default: rnext_state = rd_idle;
  endcase
end

always @(posedge m_axi_aclk) begin
  if (m_axi_aresetn == 1'b0) begin
    dout <= 32'b0;
    resp <= 2'b0;
  end else if (m_axi_rvalid == 1'b1 && m_axi_rready == 1'b1) begin
    dout <= m_axi_rdata;
    resp <= m_axi_rresp;
  end else if (m_axi_bvalid == 1'b1 && m_axi_bready == 1'b1) begin
    resp <= m_axi_bresp;
  end
end


//////////////read counter
always @(posedge m_axi_aclk) begin
  if (!m_axi_aresetn || rstate == rd_idle || rstate == wait_for_rd_op || rstate != rnext_state)
    rd_count <= 4'd0;
  else
    rd_count <= rd_count + 1'b1;
end

 


endmodule


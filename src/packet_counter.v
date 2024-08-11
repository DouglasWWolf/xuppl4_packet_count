//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 16-Dec-23  DWW     1  Initial creation
//====================================================================================

/*
    This module allows a user to define ranges of packet sizes, and counts
    incoming packets according to size
*/


module packet_counter # (parameter AW=8)
(
    input clk, resetn,

    // Input packet length
    input[15:0] plen_tdata,
    input       plen_tvalid,
    input       plen_tuser,

    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
);  

// Ranges are numbered 0 thru 7
localparam RANGE_COUNT = 8;

//=========================  AXI Register Map  =============================
localparam REG_CLEAR_COUNTERS   = 0;  // 0x0000
localparam REG_GOOD_PACKETS_H   = 16; // 0x0040
localparam REG_GOOD_PACKETS_L   = 17; // 0x0044 
localparam REG_BAD_PACKETS_H    = 18; // 0x0048
localparam REG_BAD_PACKETS_L    = 19; // 0x004C
localparam REG_UNCLAS_PACKETS_H = 20; // 0x0050
localparam REG_UNCLAS_PACKETS_L = 21; // 0x0054
localparam REG_RANGE0           = 32; // 0x0080
localparam REG_COUNTER0         = 48; // 0x00C0
//==========================================================================


//==========================================================================
// We'll communicate with the AXI4-Lite Slave core with these signals.
//==========================================================================
// AXI Slave Handler Interface for write requests
wire[31:0]  ashi_windx;     // Input   Write register-index
wire[31:0]  ashi_waddr;     // Input:  Write-address
wire[31:0]  ashi_wdata;     // Input:  Write-data
wire        ashi_write;     // Input:  1 = Handle a write request
reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
wire        ashi_widle;     // Output: 1 = Write state machine is idle

// AXI Slave Handler Interface for read requests
wire[31:0]  ashi_rindx;     // Input   Read register-index
wire[31:0]  ashi_raddr;     // Input:  Read-address
wire        ashi_read;      // Input:  1 = Handle a read request
reg[31:0]   ashi_rdata;     // Output: Read data
reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
wire        ashi_ridle;     // Output: 1 = Read state machine is idle
//==========================================================================

// The state of the state-machines that handle AXI4-Lite read and AXI4-Lite write
reg ashi_write_state, ashi_read_state;

// The AXI4 slave state machines are idle when in state 0 and their "start" signals are low
assign ashi_widle = (ashi_write == 0) && (ashi_write_state == 0);
assign ashi_ridle = (ashi_read  == 0) && (ashi_read_state  == 0);
   
// These are the valid values for ashi_rresp and ashi_wresp
localparam OKAY   = 0;
localparam SLVERR = 2;
localparam DECERR = 3;

// Create a mask that has "AW" 1-bits in a row
localparam ADDR_MASK = (1<<AW) - 1;

// At any given moment, this tracks whether plen_tdata is within one of
// the defined ranges
reg[RANGE_COUNT-1:0] in_range;

// The low-end and the hi-end of the user defined ranges (of packet sizes)
reg[15:0] range_lo[0:RANGE_COUNT-1];
reg[15:0] range_hi[0:RANGE_COUNT-1];

// Packet counters, one per defined range
reg[63:0] counter[0:RANGE_COUNT-1];

// The total number of good, bad packets, and unclassified packets received
reg[63:0] good_packets, bad_packets, unclass_packets;

// This will be high when the counters should be cleared
reg clear_counters;

//==========================================================================
// This block manages the "counter" array of packet-counters
//==========================================================================
genvar i;
for (i=0; i<RANGE_COUNT; i=i+1) begin
    
    // Create an array of bits that tracks whether this 
    // packet length is within one of the defined ranges
    always @* begin
        in_range[i] = (plen_tdata >= range_lo[i])
                    & (plen_tdata <= range_hi[i]);
    end

    always @(posedge clk) begin
        if (resetn == 0 || clear_counters)
            counter[i] <= 0;
        else if (plen_tvalid & !plen_tuser) begin
            if (in_range[i]) counter[i] <= counter[i] + 1;
        end
    end

end
//==========================================================================


//==========================================================================
// This counts unclassified packets.  An unclassified packet is a good
// packet whose length doesn't match any of the user-defined ranges
//==========================================================================
always @(posedge clk) begin
    if (resetn == 0 || clear_counters)
        unclass_packets <= 0;
    else if (plen_tvalid & !plen_tuser) begin
        if (in_range == 0) unclass_packets <= unclass_packets + 1;
    end
end
//==========================================================================




//==========================================================================
// This block counts the total number of good and bad packets
//==========================================================================
always @(posedge clk) begin
    
    if (resetn == 0 || clear_counters) begin
        good_packets <= 0;
        bad_packets  <= 0;
    end
    
    else if (plen_tvalid) begin
        if (plen_tuser)
            bad_packets <= bad_packets + 1;
        else
            good_packets <= good_packets + 1;
    end
end
//==========================================================================



//==========================================================================
// This state machine handles AXI4-Lite write requests
//
// Drives:
//==========================================================================
always @(posedge clk) begin

    clear_counters <= 0;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;

    // If we're not in reset, and a write-request has occured...        
    end else case (ashi_write_state)
        
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // Convert the byte address into a register index
                case (ashi_windx)
               
                    REG_CLEAR_COUNTERS:
                        clear_counters <= 1;

                    REG_RANGE0 + 0:
                        begin
                            range_lo[0] <= ashi_wdata[15:00];
                            range_hi[0] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 1:
                        begin
                            range_lo[1] <= ashi_wdata[15:00];
                            range_hi[1] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 2:
                        begin
                            range_lo[2] <= ashi_wdata[15:00];
                            range_hi[2] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 3:
                        begin
                            range_lo[3] <= ashi_wdata[15:00];
                            range_hi[3] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 4:
                        begin
                            range_lo[4] <= ashi_wdata[15:00];
                            range_hi[4] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 5:
                        begin
                            range_lo[5] <= ashi_wdata[15:00];
                            range_hi[5] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 6:
                        begin
                            range_lo[6] <= ashi_wdata[15:00];
                            range_hi[6] <= ashi_wdata[31:16];
                        end

                    REG_RANGE0 + 7:
                        begin
                            range_lo[7] <= ashi_wdata[15:00];
                            range_hi[7] <= ashi_wdata[31:16];
                        end

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                endcase
            end

        // Dummy state, doesn't do anything
        1: ashi_write_state <= 0;

    endcase
end
//==========================================================================





//==========================================================================
// World's simplest state machine for handling AXI4-Lite read requests
//==========================================================================
always @(posedge clk) begin
    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_read_state <= 0;
    
    // If we're not in reset, and a read-request has occured...        
    end else if (ashi_read) begin
   
        // Assume for the moment that the result will be OKAY
        ashi_rresp <= OKAY;              
        
        // Convert the byte address into a register index
        case (ashi_rindx)
            
            // Read the counter of "good" packets
            REG_GOOD_PACKETS_H:  ashi_rdata <= good_packets[63:32];
            REG_GOOD_PACKETS_L:  ashi_rdata <= good_packets[31:00];

            // Read the counter of "bad" packets
            REG_BAD_PACKETS_H:  ashi_rdata <= bad_packets[63:32];
            REG_BAD_PACKETS_L:  ashi_rdata <= bad_packets[31:00];

            // Read the counter of "unclassified" packets
            REG_UNCLAS_PACKETS_H:  ashi_rdata <= unclass_packets[63:32];
            REG_UNCLAS_PACKETS_L:  ashi_rdata <= unclass_packets[31:00];

            // Read the packet-length ranges
            REG_RANGE0   +  0: ashi_rdata <= {range_hi[0], range_lo[0]};
            REG_RANGE0   +  1: ashi_rdata <= {range_hi[1], range_lo[1]};
            REG_RANGE0   +  2: ashi_rdata <= {range_hi[2], range_lo[2]};
            REG_RANGE0   +  3: ashi_rdata <= {range_hi[3], range_lo[3]};
            REG_RANGE0   +  4: ashi_rdata <= {range_hi[4], range_lo[4]};
            REG_RANGE0   +  5: ashi_rdata <= {range_hi[5], range_lo[5]};
            REG_RANGE0   +  6: ashi_rdata <= {range_hi[6], range_lo[6]};
            REG_RANGE0   +  7: ashi_rdata <= {range_hi[7], range_lo[7]};

            // Read the high-order 32-bits of the counters
            REG_COUNTER0 +  0: ashi_rdata <= counter[0][63:32];
            REG_COUNTER0 +  2: ashi_rdata <= counter[1][63:32];
            REG_COUNTER0 +  4: ashi_rdata <= counter[2][63:32];
            REG_COUNTER0 +  6: ashi_rdata <= counter[3][63:32];
            REG_COUNTER0 +  8: ashi_rdata <= counter[4][63:32];
            REG_COUNTER0 + 10: ashi_rdata <= counter[5][63:32];
            REG_COUNTER0 + 12: ashi_rdata <= counter[6][63:32];
            REG_COUNTER0 + 14: ashi_rdata <= counter[7][63:32];

            // Read the low-order 32-bits of the counters
            REG_COUNTER0 +  1: ashi_rdata <= counter[0][31:00];
            REG_COUNTER0 +  3: ashi_rdata <= counter[1][31:00];
            REG_COUNTER0 +  5: ashi_rdata <= counter[2][31:00];
            REG_COUNTER0 +  7: ashi_rdata <= counter[3][31:00];
            REG_COUNTER0 +  9: ashi_rdata <= counter[4][31:00];
            REG_COUNTER0 + 11: ashi_rdata <= counter[5][31:00];
            REG_COUNTER0 + 13: ashi_rdata <= counter[6][31:00];
            REG_COUNTER0 + 15: ashi_rdata <= counter[7][31:00];

            // Reads of any other register are a decode-error
            default: ashi_rresp <= DECERR;
        
        endcase
    end
end
//==========================================================================



//==========================================================================
// This connects us to an AXI4-Lite slave core
//==========================================================================
axi4_lite_slave#(ADDR_MASK) axil_slave
(
    .clk            (clk),
    .resetn         (resetn),
    
    // AXI AW channel
    .AXI_AWADDR     (S_AXI_AWADDR),
    .AXI_AWVALID    (S_AXI_AWVALID),   
    .AXI_AWREADY    (S_AXI_AWREADY),
    
    // AXI W channel
    .AXI_WDATA      (S_AXI_WDATA),
    .AXI_WVALID     (S_AXI_WVALID),
    .AXI_WSTRB      (S_AXI_WSTRB),
    .AXI_WREADY     (S_AXI_WREADY),

    // AXI B channel
    .AXI_BRESP      (S_AXI_BRESP),
    .AXI_BVALID     (S_AXI_BVALID),
    .AXI_BREADY     (S_AXI_BREADY),

    // AXI AR channel
    .AXI_ARADDR     (S_AXI_ARADDR), 
    .AXI_ARVALID    (S_AXI_ARVALID),
    .AXI_ARREADY    (S_AXI_ARREADY),

    // AXI R channel
    .AXI_RDATA      (S_AXI_RDATA),
    .AXI_RVALID     (S_AXI_RVALID),
    .AXI_RRESP      (S_AXI_RRESP),
    .AXI_RREADY     (S_AXI_RREADY),

    // ASHI write-request registers
    .ASHI_WADDR     (ashi_waddr),
    .ASHI_WINDX     (ashi_windx),
    .ASHI_WDATA     (ashi_wdata),
    .ASHI_WRITE     (ashi_write),
    .ASHI_WRESP     (ashi_wresp),
    .ASHI_WIDLE     (ashi_widle),

    // ASHI read registers
    .ASHI_RADDR     (ashi_raddr),
    .ASHI_RINDX     (ashi_rindx),
    .ASHI_RDATA     (ashi_rdata),
    .ASHI_READ      (ashi_read ),
    .ASHI_RRESP     (ashi_rresp),
    .ASHI_RIDLE     (ashi_ridle)
);
//==========================================================================


endmodule

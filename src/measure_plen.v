
//=============================================================================
//               ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 09-Aug-24  DWW     1  Initial creation
//=============================================================================

/*
    Counts the number of bytes in a packet
*/

module measure_plen # (parameter DW=512)
(
    input           clk, resetn,

    // Input stream
    input[DW-1:0]   axis_in_tdata,
    input[DW/8-1:0] axis_in_tkeep,
    input           axis_in_tlast,
    input           axis_in_tuser,
    input           axis_in_tvalid,
    output          axis_in_tready,

    // Computed packet length and "valid" signal
    output[15:0]    plen_tdata,
    output          plen_tuser,
    output          plen_tvalid
);

// The number of bytes in the current beat of the input stream
reg[15:0] bytes_in_beat;

// The accumulated packet length thus far
reg[15:0] partial_plen;

// The tuser signal indicates that the current packet is corrupted
assign plen_tuser = axis_in_tuser;

// We're always ready to receive data when we're not in reset
assign axis_in_tready = (resetn == 1);

// The packet length is the accumulated length thus far, plus the 
// number of bytes in this beat
assign plen_tdata = partial_plen + bytes_in_beat;

// "plen_tdata" is valid on the last beat of every packet
assign plen_tvalid = axis_in_tvalid & axis_in_tready & axis_in_tlast;

//=============================================================================
// This block counts the number of '1' bits in axis_in_tkeep
//=============================================================================
integer i;
always @* begin
    bytes_in_beat = 0;
    for (i=0; i<(DW/8); i=i+1) begin
        if (axis_in_tkeep[i]) bytes_in_beat = bytes_in_beat + 1;
    end
end
//=============================================================================


//=============================================================================
// This block accumulates the lengthy of the packet in "partial_plen".  This
// will never include the length of the very last beat of the packet
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0)
        partial_plen <= 0;
    
    else if (axis_in_tvalid & axis_in_tready) begin
        if (axis_in_tlast)
            partial_plen <= 0;
        else
            partial_plen <= partial_plen + bytes_in_beat;
    end
end
//=============================================================================


endmodule
// mult_16bit.v

// Generated using ACDS version 16.0 211

`timescale 1 ps / 1 ps
module mult_16bit (
		input  wire [15:0] dataa,  //  mult_input.dataa
		input  wire [15:0] datab,  //            .datab
		input  wire        clock,  //            .clock
		input  wire        aclr,   //            .aclr
        input  wire        clken,  //            .clken
		output wire [31:0] result  // mult_output.result
	);

	mult_16bit_lpm_mult_160_5m6gjka lpm_mult_0 (
		.dataa  (dataa),  //  mult_input.dataa
		.datab  (datab),  //            .datab
		.clock  (clock),  //            .clock
		.aclr   (aclr),   //            .aclr
        .clken  (clken),  //            .clken
		.result (result)  // mult_output.result
	);

endmodule
// pcs_if.sv
//
// Interface PCS 10GBASE-R (lado SERDES del DUT): un bloque 64B/66B por ciclo.

interface pcs_if (input logic clk);

    logic [63:0] data;    // payload del bloque, scrambleado
    logic [1:0]  header;  // sync header, sin scramblear

endinterface

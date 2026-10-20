// xgmii_if.sv
//
// Interface XGMII: punto de contacto entre el agente y el DUT.
//
// Idea:
// - El generador escribe en una instancia de esta interface y el checker lee
//   de otra (o de la misma). Ninguno de los dos se conecta directo al DUT.
// - En tb_top se decide qué instancia va a qué puerto del DUT:
//   generador -> xgmii_txd/xgmii_txc, checker <- xgmii_rxd/xgmii_rxc.

interface xgmii_if (input logic clk);

    logic [63:0] d;   // 8 lanes de 1 byte. Lane 0 = d[7:0]
    logic [7:0]  c;   // 1 bit por bloque de 8 bytes: 0 = dato, 1 = control

endinterface

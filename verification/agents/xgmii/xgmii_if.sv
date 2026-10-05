// xgmii_if.sv
//
// Interface XGMII: punto de contacto entre el agente y el DUT.
//
// Idea:
// - El generador escribe en una instancia de esta interface y el checker lee
//   de otra (o de la misma). Ninguno de los dos se conecta directo al DUT.
// - En tb_top se decide qué instancia va a qué puerto del DUT:
//   generador -> xgmii_txd/xgmii_txc, checker <- xgmii_rxd/xgmii_rxc.


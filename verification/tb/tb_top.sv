// tb_top.sv
//
// Top del testbench.
//
// - Instancia el DUT y los agentes XGMII y PCS (generador + checker c/u).
// - El checker XGMII siempre mira xgmii_rxd/rxc y el checker PCS siempre mira
//   serdes_tx. Lo que cambia es de dónde vienen las entradas del DUT, según
//   loopback_xgmii (lo elige el test, por defecto 0):
//   0: tests XGMII. Loopback serdes: la salida serdes del TX vuelve al RX.
//      xgmii_gen -> TX -> serdes_tx -> serdes_rx -> RX -> xgmii_checker
//                          serdes_tx -> pcs_checker
//   1: tests PCS. Loopback XGMII: la salida XGMII del RX vuelve al TX.
//      pcs_gen -> serdes_rx -> RX -> xgmii_rxd/rxc -> xgmii_checker
//                                    xgmii_rxd/rxc -> TX -> serdes_tx -> pcs_checker
// - No tiene tests. Instancia "test u_test": cada archivo de test define un
//   módulo llamado test, y se compila uno solo por simulación.
// - Clocks, reset y start los maneja Python (cocotb). done lo pone el test.

module tb_top (
    input  logic tx_clk,
    input  logic rx_clk,
    input  logic tx_rst,
    input  logic rx_rst,
    input  logic start,    // Python: arrancar el test
    output logic done      // test: terminó
);

    // Interfaces XGMII: una para el lado TX y otra para el lado RX
    xgmii_if x_if_tx (tx_clk);
    xgmii_if x_if_rx (rx_clk);

    // Interfaces PCS: salida serdes del TX y entrada serdes del RX
    pcs_if p_if_tx (tx_clk);
    pcs_if p_if_rx (rx_clk);

    // Agentes
    xgmii_gen     u_xgmii_gen (x_if_tx);
    xgmii_checker u_xgmii_chk (x_if_rx);
    pcs_gen       u_pcs_gen   (p_if_rx);
    pcs_checker   u_pcs_chk   (p_if_tx);

    // Selección del loopback
    logic loopback_xgmii = 0;

    // Entrada XGMII del TX: xgmii_gen o la salida XGMII del RX
    logic [63:0] xgmii_txd;
    logic [7:0]  xgmii_txc;

    assign xgmii_txd = loopback_xgmii ? x_if_rx.data    : x_if_tx.data;
    assign xgmii_txc = loopback_xgmii ? x_if_rx.control : x_if_tx.control;

    // Entrada serdes del RX: la salida serdes del TX o pcs_gen
    logic        serdes_tx_data_valid;
    logic        serdes_tx_hdr_valid;
    logic [63:0] serdes_rx_data;
    logic        serdes_rx_data_valid;
    logic [1:0]  serdes_rx_hdr;
    logic        serdes_rx_hdr_valid;

    assign serdes_rx_data       = loopback_xgmii ? p_if_rx.data   : p_if_tx.data;
    assign serdes_rx_data_valid = loopback_xgmii ? 1'b1           : serdes_tx_data_valid;
    assign serdes_rx_hdr        = loopback_xgmii ? p_if_rx.header : p_if_tx.header;
    assign serdes_rx_hdr_valid  = loopback_xgmii ? 1'b1           : serdes_tx_hdr_valid;

    // DUT
    taxi_eth_phy_10g dut (
        .rx_clk                  (rx_clk),
        .rx_rst                  (rx_rst),
        .tx_clk                  (tx_clk),
        .tx_rst                  (tx_rst),

        // XGMII
        .xgmii_txd               (xgmii_txd),
        .xgmii_txc               (xgmii_txc),
        .xgmii_tx_valid          (1'b1),
        .xgmii_rxd               (x_if_rx.data),
        .xgmii_rxc               (x_if_rx.control),
        .xgmii_rx_valid          (),
        .tx_gbx_req_sync         (),
        .tx_gbx_req_stall        (),
        .tx_gbx_sync             (1'b0),
        .rx_gbx_sync             (),

        // SERDES
        .serdes_tx_data          (p_if_tx.data),
        .serdes_tx_data_valid    (serdes_tx_data_valid),
        .serdes_tx_hdr           (p_if_tx.header),
        .serdes_tx_hdr_valid     (serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync  (1'b0),
        .serdes_tx_gbx_req_stall (1'b0),
        .serdes_tx_gbx_sync      (),
        .serdes_rx_data          (serdes_rx_data),
        .serdes_rx_data_valid    (serdes_rx_data_valid),
        .serdes_rx_hdr           (serdes_rx_hdr),
        .serdes_rx_hdr_valid     (serdes_rx_hdr_valid),
        .serdes_rx_gbx_sync      (1'b0),
        .serdes_rx_bitslip       (),
        .serdes_rx_reset_req     (),

        // Status
        .tx_bad_block            (),
        .rx_error_count          (),
        .rx_bad_block            (),
        .rx_sequence_error       (),
        .rx_block_lock           (),
        .rx_high_ber             (),
        .rx_status               (),

        // Configuración
        .cfg_tx_prbs31_enable    (1'b0),
        .cfg_rx_prbs31_enable    (1'b0)
    );

    // Test (el módulo test viene del archivo de test que se compile)
    test u_test (
        .start (start),
        .done  (done)
    );

    // Ondas para GTKWave: se activan con el plusarg +waves (WAVES=1 en Python)
    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("waves.fst");
            $dumpvars(0, tb_top);
        end
    end

endmodule

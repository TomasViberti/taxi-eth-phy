// tb_top.sv
//
// Top del testbench.
//
// - Instancia el DUT, el generador y el checker XGMII.
// - Loopback: la salida serdes del TX vuelve a la entrada serdes del RX.
//   generador -> xgmii_txd/txc -> TX -> serdes_tx -> serdes_rx -> RX -> xgmii_rxd/rxc -> checker
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

    // Agente
    xgmii_gen     u_gen (x_if_tx);
    xgmii_checker u_chk (x_if_rx);

    // Loopback serdes
    logic [63:0] serdes_tx_data;
    logic        serdes_tx_data_valid;
    logic [1:0]  serdes_tx_hdr;
    logic        serdes_tx_hdr_valid;

    // DUT
    taxi_eth_phy_10g dut (
        .rx_clk                  (rx_clk),
        .rx_rst                  (rx_rst),
        .tx_clk                  (tx_clk),
        .tx_rst                  (tx_rst),

        // XGMII
        .xgmii_txd               (x_if_tx.d),
        .xgmii_txc               (x_if_tx.c),
        .xgmii_tx_valid          (1'b1),
        .xgmii_rxd               (x_if_rx.d),
        .xgmii_rxc               (x_if_rx.c),
        .xgmii_rx_valid          (),
        .tx_gbx_req_sync         (),
        .tx_gbx_req_stall        (),
        .tx_gbx_sync             (1'b0),
        .rx_gbx_sync             (),

        // SERDES con loopback
        .serdes_tx_data          (serdes_tx_data),
        .serdes_tx_data_valid    (serdes_tx_data_valid),
        .serdes_tx_hdr           (serdes_tx_hdr),
        .serdes_tx_hdr_valid     (serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync  (1'b0),
        .serdes_tx_gbx_req_stall (1'b0),
        .serdes_tx_gbx_sync      (),
        .serdes_rx_data          (serdes_tx_data),
        .serdes_rx_data_valid    (serdes_tx_data_valid),
        .serdes_rx_hdr           (serdes_tx_hdr),
        .serdes_rx_hdr_valid     (serdes_tx_hdr_valid),
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

endmodule

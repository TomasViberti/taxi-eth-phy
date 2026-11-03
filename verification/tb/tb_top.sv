// tb_top.sv

module tb_top (
    input  logic tx_clk,
    input  logic rx_clk,
    input  logic tx_rst,
    input  logic rx_rst,
    input  logic start,    // Python: arrancar el test
    output logic done      // test: terminó
);

    // Selección del loopback
    logic loopback_xgmii = 0;

    // XGMII de 64 bits

    // Salida del generador XGMII (hace de RS del lado TX)
    logic [63:0] gen_txd;
    logic [7:0]  gen_txc;

    // Entrada XGMII del TX del DUT: xgmii_gen o la salida XGMII del RX
    logic [63:0] xgmii_txd;
    logic [7:0]  xgmii_txc;

    // Salida XGMII del RX del DUT (la mira el checker XGMII)
    logic [63:0] xgmii_rxd;
    logic [7:0]  xgmii_rxc;

    assign xgmii_txd = loopback_xgmii ? xgmii_rxd : gen_txd;
    assign xgmii_txc = loopback_xgmii ? xgmii_rxc : gen_txc;

    // Serdes: un bloque 64B/66B por ciclo, payload + sync header

    // Salida del generador PCS
    logic [63:0] gen_rx_data;
    logic [1:0]  gen_rx_hdr;

    // Salida serdes del TX del DUT (la mira el checker PCS)
    logic [63:0] serdes_tx_data;
    logic        serdes_tx_data_valid;
    logic [1:0]  serdes_tx_hdr;
    logic        serdes_tx_hdr_valid;

    // Entrada serdes del RX del DUT: la salida serdes del TX o pcs_gen
    logic [63:0] serdes_rx_data;
    logic        serdes_rx_data_valid;
    logic [1:0]  serdes_rx_hdr;
    logic        serdes_rx_hdr_valid;

    assign serdes_rx_data       = loopback_xgmii ? gen_rx_data : serdes_tx_data;
    assign serdes_rx_data_valid = loopback_xgmii ? 1'b1        : serdes_tx_data_valid;
    assign serdes_rx_hdr        = loopback_xgmii ? gen_rx_hdr  : serdes_tx_hdr;
    assign serdes_rx_hdr_valid  = loopback_xgmii ? 1'b1        : serdes_tx_hdr_valid;

    // Agentes

    xgmii_gen     u_xgmii_gen (.clk(tx_clk), .txd(gen_txd),   .txc(gen_txc));
    xgmii_checker u_xgmii_chk (.clk(rx_clk), .rxd(xgmii_rxd), .rxc(xgmii_rxc));
    pcs_gen       u_pcs_gen   (.clk(rx_clk), .rx_data(gen_rx_data),    .rx_hdr(gen_rx_hdr));
    pcs_checker   u_pcs_chk   (.clk(tx_clk), .tx_data(serdes_tx_data), .tx_hdr(serdes_tx_hdr));

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
        .xgmii_rxd               (xgmii_rxd),
        .xgmii_rxc               (xgmii_rxc),
        .xgmii_rx_valid          (),
        .tx_gbx_req_sync         (),
        .tx_gbx_req_stall        (),
        .tx_gbx_sync             (1'b0),
        .rx_gbx_sync             (),

        // SERDES
        .serdes_tx_data          (serdes_tx_data),
        .serdes_tx_data_valid    (serdes_tx_data_valid),
        .serdes_tx_hdr           (serdes_tx_hdr),
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

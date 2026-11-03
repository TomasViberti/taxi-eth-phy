// test_term_lanes.sv
//
// Terminate en cada una de las 8 lanes: 8 frames, el FD del frame k cae en
// la lane k.
// - Lado PCS: cada posición usa un block type distinto (figura 49-7):
//   0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF.
// - Lado XGMII: los 8 frames tienen que salir bien formados y con el payload
//   PRBS31 intacto.
// Pasa si error_count == 0 en los dos checkers.

module test (input logic start, output logic done);

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_xgmii_gen.send_idle(1);
        tb_top.u_xgmii_gen.send_idle(10);

        // Los dos checkers cuentan desde acá
        tb_top.u_pcs_chk.clear();
        tb_top.u_xgmii_chk.clear();

        for (int k = 0; k < 8; k++) tb_top.u_xgmii_gen.send_frame(2, k);
        tb_top.u_xgmii_gen.send_idle(20);

        // Salida serdes del TX
        tb_top.u_pcs_chk.check_counts(.frames(8), .e(0), .prbs(0), .seq(0));
        // Salida XGMII del RX, después del loopback serdes
        tb_top.u_xgmii_chk.check_counts(.frames(8), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

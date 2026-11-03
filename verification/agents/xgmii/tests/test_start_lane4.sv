// test_start_lane4.sv
//
// Start en lane 4. En 64 bits es válido: la lane 4 es la lane 0 de la segunda
// palabra de 32.
// - Lado PCS: block type 0x33 (4 /I/, 4 bits en 0 y 3 bytes de preámbulo),
//   datos corridos 4 bytes y terminate 0xCC.
// - Lado XGMII: los 2 frames tienen que salir bien formados, con el /S/ en
//   lane 4. El checker avanza byte a byte, así que el corrimiento no cambia nada.
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

        tb_top.u_xgmii_gen.send_frame_lane4(4);
        tb_top.u_xgmii_gen.send_frame_lane4(1);
        tb_top.u_xgmii_gen.send_idle(20);

        // Salida serdes del TX
        tb_top.u_pcs_chk.check_counts(.frames(2), .e(0), .prbs(0), .seq(0));
        // Salida XGMII del RX, después del loopback serdes
        tb_top.u_xgmii_chk.check_counts(.frames(2), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

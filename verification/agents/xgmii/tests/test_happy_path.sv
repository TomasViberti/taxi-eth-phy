// test_happy_path.sv
//
// Happy path: frames correctos de distintos largos.
// - Lado PCS: lo que sale por serdes_tx, descrambleado, tienen que ser los
//   bloques de la figura 49-7 (start 0x78, datos, terminate según la lane).
// - Lado XGMII: los 3 frames tienen que salir bien formados (cl. 46.2) y con
//   el payload PRBS31 intacto. Sin /E/ ni errores.
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

        tb_top.u_xgmii_gen.send_frame(8, 0);
        tb_top.u_xgmii_gen.send_frame(1, 4);
        tb_top.u_xgmii_gen.send_frame(20, 7);
        tb_top.u_xgmii_gen.send_idle(20);

        // Salida serdes del TX
        tb_top.u_pcs_chk.check_counts(.frames(3), .e(0), .prbs(0), .seq(0));
        // Salida XGMII del RX, después del loopback serdes
        tb_top.u_xgmii_chk.check_counts(.frames(3), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

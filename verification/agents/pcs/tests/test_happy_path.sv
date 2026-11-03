// test_happy_path.sv
//
// Happy path PCS: frames correctos de distintos largos, con loopback XGMII.
// pcs_gen -> RX -> XGMII RX -> TX -> serdes_tx
// - Lo que sale por XGMII RX tienen que ser los 4 frames bien formados
//   (cl. 46.2) y con el payload PRBS31 intacto (cl. 49.2.13, decodificación).
// - Lo que sale por serdes_tx, descrambleado, tienen que ser los mismos
//   bloques que mandó pcs_gen (figura 49-7).
// Pasa si error_count == 0 en los dos checkers.

module test (input logic start, output logic done);

    // Loopback XGMII: el RX recibe lo que manda pcs_gen y su salida XGMII vuelve al TX
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        // Los dos checkers cuentan desde acá
        tb_top.u_pcs_chk.clear();
        tb_top.u_xgmii_chk.clear();

        tb_top.u_pcs_gen.send_frame(8, 0);
        tb_top.u_pcs_gen.send_frame(1, 4);
        tb_top.u_pcs_gen.send_frame(20, 7);
        tb_top.u_pcs_gen.send_frame_lane4(4);
        tb_top.u_pcs_gen.send_idle(20);

        // Salida XGMII del RX
        tb_top.u_xgmii_chk.check_counts(.frames(4), .e(0), .prbs(0), .seq(0));
        // Salida serdes del TX, después de dar la vuelta
        tb_top.u_pcs_chk.check_counts(.frames(4), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

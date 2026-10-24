// test_happy_path.sv
//
// Happy path PCS: frames correctos de distintos largos, con loopback XGMII.
// pcs_gen -> RX -> XGMII RX -> TX -> serdes_tx
// - Lo que sale por XGMII RX tiene que ser el frame equivalente
//   (cl. 49.2.13, decodificación).
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

        fork
            begin
                tb_top.u_pcs_gen.send_frame(8, 0);
                tb_top.u_pcs_gen.send_frame(1, 4);
                tb_top.u_pcs_gen.send_frame(20, 7);
                tb_top.u_pcs_gen.send_frame_lane4(4);
                tb_top.u_pcs_gen.send_idle(20);
            end
            // Salida XGMII del RX
            begin
                tb_top.u_xgmii_chk.expect_frame(8, 0);
                tb_top.u_xgmii_chk.expect_frame(1, 4);
                tb_top.u_xgmii_chk.expect_frame(20, 7);
                tb_top.u_xgmii_chk.expect_frame_lane4(4);
            end
            // Salida serdes del TX, después de dar la vuelta
            begin
                tb_top.u_pcs_chk.expect_frame(8, 0);
                tb_top.u_pcs_chk.expect_frame(1, 4);
                tb_top.u_pcs_chk.expect_frame(20, 7);
                tb_top.u_pcs_chk.expect_frame_lane4(4);
            end
        join_none
        // join_none + wait fork en vez de join: ver xgmii/tests/test_happy_path.sv
        wait fork;

        done = 1;
    end

endmodule

// test_happy_path.sv
//
// Happy path: frames correctos de distintos largos.
// - Lado PCS: lo que sale por serdes_tx, descrambleado, tienen que ser los
//   bloques de la figura 49-7 (start 0x78, datos, terminate según la lane).
// - Lado XGMII: lo que sale por XGMII RX tiene que ser igual a lo que entró
//   por XGMII TX.
// Pasa si error_count == 0 en los dos checkers.

module test (input logic start, output logic done);

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_xgmii_gen.send_idle(1);
        tb_top.u_xgmii_gen.send_idle(10);

        fork
            begin
                tb_top.u_xgmii_gen.send_frame(8, 0);
                tb_top.u_xgmii_gen.send_frame(1, 4);
                tb_top.u_xgmii_gen.send_frame(20, 7);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.expect_frame(8, 0);
                tb_top.u_pcs_chk.expect_frame(1, 4);
                tb_top.u_pcs_chk.expect_frame(20, 7);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.expect_frame(8, 0);
                tb_top.u_xgmii_chk.expect_frame(1, 4);
                tb_top.u_xgmii_chk.expect_frame(20, 7);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

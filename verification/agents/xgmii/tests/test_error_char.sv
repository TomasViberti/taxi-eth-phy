// test_error_char.sv
//
// Carácter de error (0xFE) en medio de un frame: palabra de dato con 0xFE en
// lane 3 (c=1 sólo en esa lane).
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): la palabra no es D, S,
// T ni C, así que es E. En TX_D pasa a TX_E y el TX manda un bloque de error.
// El dato siguiente vuelve a TX_D y el frame sigue.
// - Lado PCS: start, 2 datos, bloque de error (0x1E con 8 /E/), 1 dato y
//   terminate.
// - Lado XGMII: start, 2 datos, 0xFE en las 8 lanes, 1 dato y terminate.
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
                tb_top.u_xgmii_gen.send_start();
                tb_top.u_xgmii_gen.send_data(2);
                // dato con 0xFE en lane 3
                tb_top.u_xgmii_gen.send_word(64'h11223344_FE667788, 8'b0000_1000);
                tb_top.u_xgmii_gen.send_data(1);
                tb_top.u_xgmii_gen.send_terminate(4);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.expect_start();
                tb_top.u_pcs_chk.expect_data(2);
                tb_top.u_pcs_chk.expect_error_block();
                tb_top.u_pcs_chk.expect_data(1);
                tb_top.u_pcs_chk.expect_terminate(4);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.expect_start();
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_error_word();
                tb_top.u_xgmii_chk.expect_data(1);
                tb_top.u_xgmii_chk.expect_terminate(4);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

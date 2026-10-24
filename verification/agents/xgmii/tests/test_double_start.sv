// test_double_start.sv
//
// Dos start seguidos sin terminate: start, start, 2 palabras de dato y
// terminate en lane 3.
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): el primer start pasa de
// TX_C a TX_D. El segundo start llega en TX_D -> TX_E, y el TX manda un bloque
// de error (EBLOCK_T). Los datos siguientes vuelven a TX_D y pasan normal.
// - Lado PCS: start, bloque de error (0x1E con 8 /E/), 2 datos y terminate.
// - Lado XGMII: start, 0xFE en las 8 lanes, los 2 datos y el terminate.
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
                tb_top.u_xgmii_gen.send_start();
                tb_top.u_xgmii_gen.send_data(2);
                tb_top.u_xgmii_gen.send_terminate(3);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.expect_start();
                tb_top.u_pcs_chk.expect_error_block();
                tb_top.u_pcs_chk.expect_data(2);
                tb_top.u_pcs_chk.expect_terminate(3);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.expect_start();
                tb_top.u_xgmii_chk.expect_error_word();
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_terminate(3);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

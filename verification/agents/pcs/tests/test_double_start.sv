// test_double_start.sv
//
// Dos start seguidos sin terminate: start, start, 2 datos y terminate.
// Norma (cl. 49.2.13.2.3, recepción): el primer start pasa de RX_C a RX_D. El
// segundo start llega en RX_D -> RX_E: sale la palabra de error (0xFE en las
// 8 lanes). Los datos siguientes vuelven a RX_D y pasan normal.
// Pasa si error_count == 0.

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
                tb_top.u_pcs_gen.send_start();
                tb_top.u_pcs_gen.send_start();
                tb_top.u_pcs_gen.send_data(2);
                tb_top.u_pcs_gen.send_terminate(3);
                tb_top.u_pcs_gen.send_idle(20);
            end
            begin
                tb_top.u_xgmii_chk.expect_start();
                tb_top.u_xgmii_chk.expect_error_word();
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_terminate(3);
            end
        join_none
        // join_none + wait fork en vez de join: ver xgmii/tests/test_happy_path.sv
        wait fork;

        done = 1;
    end

endmodule

// test_bad_sync_hdr.sv
//
// Sync header inválido (00 y 11), entre idles y en medio de un frame.
// Norma : un bloque con header 00 o 11 es de tipo E. 
// Entre idles (RX_C) y dentro del frame (RX_D) pasa a RX_E y del lado
// XGMII RX sale una palabra de error (0xFE en las 8 lanes). El bloque
// siguiente sale normal: C en RX_E -> RX_C, D en RX_E -> RX_D.
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
                // Entre idles: idle con header 00 y con header 11
                tb_top.u_pcs_gen.send_idle_hdr(2'b00);
                tb_top.u_pcs_gen.send_idle(20);
                tb_top.u_pcs_gen.send_idle_hdr(2'b11);
                tb_top.u_pcs_gen.send_idle(20);

                // Dentro del frame: un dato con header 00 y otro con 11
                tb_top.u_pcs_gen.send_start();
                tb_top.u_pcs_gen.send_data(2);
                tb_top.u_pcs_gen.send_data_hdr(2'b00);
                tb_top.u_pcs_gen.send_data(2);
                tb_top.u_pcs_gen.send_data_hdr(2'b11);
                tb_top.u_pcs_gen.send_data(1);
                tb_top.u_pcs_gen.send_terminate(3);
                tb_top.u_pcs_gen.send_idle(20);
            end
            begin
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);

                tb_top.u_xgmii_chk.expect_start();
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_error_word();
                tb_top.u_xgmii_chk.skip_data(1);
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_error_word();
                tb_top.u_xgmii_chk.skip_data(1);
                tb_top.u_xgmii_chk.expect_data(1);
                tb_top.u_xgmii_chk.expect_terminate(3);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

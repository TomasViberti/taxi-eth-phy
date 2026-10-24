// test_bad_ctrl.sv
//
// Códigos que no existen en la norma, entre idles:
// - bloque 0x1E con un código de control de 7 bits que no está en la
//   tabla 49-1 (0x01 en la posición 3, el resto /I/)
// - block type que no está en la figura 49-7 (0x00 y 0x11)
// Norma (cl. 49.2.13.2.3, recepción): el bloque no es C, S, T ni D, así que
// es de tipo E. En RX_C pasa a RX_E y del lado XGMII RX sale la palabra de
// error completa (0xFE en las 8 lanes), no sólo en la posición del código.
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
                tb_top.u_pcs_gen.send_ctrl_code(3, 7'h01);
                tb_top.u_pcs_gen.send_idle(20);
                tb_top.u_pcs_gen.send_block_type(8'h00);
                tb_top.u_pcs_gen.send_idle(20);
                tb_top.u_pcs_gen.send_block_type(8'h11);
                tb_top.u_pcs_gen.send_idle(20);
            end
            begin
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
            end
        join_none
        // join_none + wait fork en vez de join: ver xgmii/tests/test_happy_path.sv
        wait fork;

        done = 1;
    end

endmodule

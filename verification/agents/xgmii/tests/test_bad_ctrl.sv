// test_bad_ctrl.sv
//
// Caracteres de control que no existen en la tabla 46-3, entre idles:
// - 0x55 con c=1 en las 8 lanes
// - 0x00 con c=1 en una sola lane (lane 3), el resto idle
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): una palabra con un
// carácter de control inválido no es C, así que es E. En TX_C pasa a TX_E y
// el TX manda un bloque de error entero, aunque el carácter inválido esté en
// una sola lane. Después los idles vuelven a TX_C.
// - Lado PCS: bloque de error (0x1E con 8 /E/) y después idles.
// - Lado XGMII: 0xFE en las 8 lanes y después idles.
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
                tb_top.u_xgmii_gen.send_word({8{8'h55}}, 8'hFF);
                tb_top.u_xgmii_gen.send_idle(20);
                tb_top.u_xgmii_gen.send_word({{4{8'h07}}, 8'h00, {3{8'h07}}}, 8'hFF);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.wait_error_block();
                tb_top.u_pcs_chk.expect_idle(4);
                tb_top.u_pcs_chk.wait_error_block();
                tb_top.u_pcs_chk.expect_idle(4);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
                tb_top.u_xgmii_chk.wait_error_word();
                tb_top.u_xgmii_chk.expect_idle(4);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

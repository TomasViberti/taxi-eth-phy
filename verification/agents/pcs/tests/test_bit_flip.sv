// test_bit_flip.sv
//
// Un bit invertido en la línea dentro del dato de un frame.
// Norma: el descrambler es 1 + x^39 + x^58, así que un bit
// errado en la posición k de la línea sale errado en k, k+39 y k+58: 3 bits
// errados, no 1.
// - bit 0: los 3 errores caen en el mismo bloque (bits 0, 39 y 58)
// - bit 20: errores en los bits 20 y 59 del bloque y en el bit 14 (78-64) del
//   bloque siguiente
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
                tb_top.u_pcs_gen.send_data(2);
                tb_top.u_pcs_gen.send_data_flip(0);
                tb_top.u_pcs_gen.send_data(3);
                tb_top.u_pcs_gen.send_data_flip(20);
                tb_top.u_pcs_gen.send_data(3);
                tb_top.u_pcs_gen.send_terminate(2);
                tb_top.u_pcs_gen.send_idle(20);
            end
            begin
                tb_top.u_xgmii_chk.expect_start();
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_data_mask((64'd1 << 0) | (64'd1 << 39) | (64'd1 << 58));
                tb_top.u_xgmii_chk.expect_data(3);
                tb_top.u_xgmii_chk.expect_data_mask((64'd1 << 20) | (64'd1 << 59));
                tb_top.u_xgmii_chk.expect_data_mask(64'd1 << 14);
                tb_top.u_xgmii_chk.expect_data(2);
                tb_top.u_xgmii_chk.expect_terminate(2);
            end
        join_none
        // join_none + wait fork en vez de join: ver xgmii/tests/test_happy_path.sv
        wait fork;

        done = 1;
    end

endmodule

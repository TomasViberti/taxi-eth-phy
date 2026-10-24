// test_start_term.sv
//
// Start inmediatamente seguido de terminate, sin palabras de dato en el medio.
// Dos casos: FD en lane 0 (frame vacío) y FD en lane 5 (5 bytes de dato).
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): start en TX_C -> TX_D,
// terminate en TX_D -> TX_T. Es una secuencia válida.
// - Lado PCS: start 0x78 seguido directo del terminate (0x87 y 0xD2).
// - Lado XGMII: tienen que salir las mismas palabras.
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
                tb_top.u_xgmii_gen.send_frame(0, 0);
                tb_top.u_xgmii_gen.send_frame(0, 5);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.expect_frame(0, 0);
                tb_top.u_pcs_chk.expect_frame(0, 5);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.expect_frame(0, 0);
                tb_top.u_xgmii_chk.expect_frame(0, 5);
            end
        join_none
        // join_none + wait fork en vez de join: Verilator 5.036 genera C++
        // que no compila con join cuando hay varias ramas begin/end
        wait fork;

        done = 1;
    end

endmodule

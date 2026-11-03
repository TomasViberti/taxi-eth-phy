// test_start_term.sv
//
// Start inmediatamente seguido de terminate, sin palabras de dato en el medio.
// Dos casos: FD en lane 0 (frame vacío) y FD en lane 5 (5 bytes de dato).
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): start en TX_C -> TX_D,
// terminate en TX_D -> TX_T. Es una secuencia válida.
// - Lado PCS: start 0x78 seguido directo del terminate (0x87 y 0xD2).
// - Lado XGMII: los 2 frames tienen que salir bien formados. El primero no
//   tiene datos y el segundo tiene 40 bits (los 31 primeros sincronizan la
//   PRBS y se verifican los 9 restantes).
// Pasa si error_count == 0 en los dos checkers.

module test (input logic start, output logic done);

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_xgmii_gen.send_idle(1);
        tb_top.u_xgmii_gen.send_idle(10);

        // Los dos checkers cuentan desde acá
        tb_top.u_pcs_chk.clear();
        tb_top.u_xgmii_chk.clear();

        tb_top.u_xgmii_gen.send_frame(0, 0);
        tb_top.u_xgmii_gen.send_frame(0, 5);
        tb_top.u_xgmii_gen.send_idle(20);

        // Salida serdes del TX
        tb_top.u_pcs_chk.check_counts(.frames(2), .e(0), .prbs(0), .seq(0));
        // Salida XGMII del RX, después del loopback serdes
        tb_top.u_xgmii_chk.check_counts(.frames(2), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

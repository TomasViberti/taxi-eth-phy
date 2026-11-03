// test_double_start.sv
//
// Dos start seguidos sin terminate: start, start, 2 palabras de dato y
// terminate en lane 3.
// Pasa si error_count == 0 en los dos checkers.

module test (input logic start, output logic done);

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_xgmii_gen.send_idle(1);
        tb_top.u_xgmii_gen.send_idle(10);

        // Los dos checkers arrancan
        tb_top.u_pcs_chk.clear();
        tb_top.u_xgmii_chk.clear();

        tb_top.u_xgmii_gen.send_start();
        tb_top.u_xgmii_gen.send_start();
        tb_top.u_xgmii_gen.send_data(2);
        tb_top.u_xgmii_gen.send_terminate(3);
        tb_top.u_xgmii_gen.send_idle(20);

        // Salida serdes del TX
        tb_top.u_pcs_chk.check_counts(.frames(0), .e(8), .prbs(0), .seq(0));
        // Salida XGMII del RX, después del loopback serdes
        tb_top.u_xgmii_chk.check_counts(.frames(0), .e(8), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

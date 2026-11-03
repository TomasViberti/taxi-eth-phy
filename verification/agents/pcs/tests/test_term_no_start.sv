// test_term_no_start.sv
//
// Terminate sin start previo, entre idles.
// Norma (cl. 49.2.13.2.3, recepción): un bloque T en RX_C pasa a RX_E. Del
// lado XGMII RX tiene que salir la palabra de error (0xFE en las 8 lanes) y
// después idles (C en RX_E -> RX_C).
// - Lado XGMII: 8 /E/.
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

        // El checker XGMII cuenta desde acá
        tb_top.u_xgmii_chk.clear();

        tb_top.u_pcs_gen.send_terminate(3);
        tb_top.u_pcs_gen.send_idle(20);

        // Salida XGMII del RX
        tb_top.u_xgmii_chk.check_counts(.frames(0), .e(8), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

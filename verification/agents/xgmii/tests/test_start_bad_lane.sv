// test_start_bad_lane.sv
//
// Start en una lane no permitida (1, 2, 3, 5, 6, 7). Según la norma sólo
// puede ir en la lane 0 o en la 4.
// Norma (cl. 49.2.13.2.3, máquina de estados del TX): la palabra no es S
// válido, así que es E. En TX_C pasa a TX_E y el TX manda un bloque de error.
// Después los idles vuelven a TX_C.
// - Lado PCS: por cada start, bloque de error (0x1E con 8 /E/) e idles.
// - Lado XGMII: por cada start, 0xFE en las 8 lanes e idles.
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
                for (int lane = 1; lane < 8; lane++) begin
                    if (lane == 4) continue;   // lane 4 es válida
                    tb_top.u_xgmii_gen.send_start_lane(lane);
                    tb_top.u_xgmii_gen.send_idle(20);
                end
            end
            // Salida serdes del TX
            begin
                repeat (6) begin
                    tb_top.u_pcs_chk.wait_error_block();
                    tb_top.u_pcs_chk.expect_idle(4);
                end
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                repeat (6) begin
                    tb_top.u_xgmii_chk.wait_error_word();
                    tb_top.u_xgmii_chk.expect_idle(4);
                end
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

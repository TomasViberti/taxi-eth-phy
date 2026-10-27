// test_term_lanes.sv
//
// Terminate en cada una de las 8 lanes: 8 frames, el FD del frame k cae en
// la lane k.
// - Lado PCS: cada posición usa un block type distinto (figura 49-7):
//   0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF.
// - Lado XGMII: los frames tienen que salir iguales.
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
                for (int k = 0; k < 8; k++) tb_top.u_xgmii_gen.send_frame(2, k);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                for (int k = 0; k < 8; k++) tb_top.u_pcs_chk.expect_frame(2, k);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                for (int k = 0; k < 8; k++) tb_top.u_xgmii_chk.expect_frame(2, k);
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule

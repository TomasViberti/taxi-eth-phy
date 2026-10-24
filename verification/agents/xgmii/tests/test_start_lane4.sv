// test_start_lane4.sv
//
// Start en lane 4. En 64 bits es válido: la lane 4 es la lane 0 de la segunda
// palabra de 32.
// - Lado PCS: block type 0x33 (4 /I/, 4 bits en 0 y 3 bytes de preámbulo),
//   datos corridos 4 bytes y terminate 0xCC.
// - Lado XGMII: el frame tiene que salir igual, corrido 4 bytes.
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
                tb_top.u_xgmii_gen.send_frame_lane4(4);
                tb_top.u_xgmii_gen.send_frame_lane4(1);
                tb_top.u_xgmii_gen.send_idle(20);
            end
            // Salida serdes del TX
            begin
                tb_top.u_pcs_chk.expect_frame_lane4(4);
                tb_top.u_pcs_chk.expect_frame_lane4(1);
            end
            // Salida XGMII del RX, después del loopback serdes
            begin
                tb_top.u_xgmii_chk.expect_frame_lane4(4);
                tb_top.u_xgmii_chk.expect_frame_lane4(1);
            end
        join_none
        // join_none + wait fork en vez de join: Verilator 5.036 genera C++
        // que no compila con join cuando hay varias ramas begin/end
        wait fork;

        done = 1;
    end

endmodule

// test_start_lane4.sv
//
// Start en lane 4. En 64 bits es válido: la lane 4 es la lane 0 de la segunda
// palabra de 32 (block type 0x33 del lado PCS). El frame tiene que salir igual,
// corrido 4 bytes.
// Pasa si error_count == 0.

module test (input logic start, output logic done);

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_gen.send_idle(1);
        tb_top.u_gen.send_idle(10);

        fork
            begin
                tb_top.u_gen.send_frame_lane4(4);
                tb_top.u_gen.send_frame_lane4(1);
                tb_top.u_gen.send_idle(20);
            end
            begin
                tb_top.u_chk.expect_frame_lane4(4);
                tb_top.u_chk.expect_frame_lane4(1);
            end
        join

        done = 1;
    end

endmodule

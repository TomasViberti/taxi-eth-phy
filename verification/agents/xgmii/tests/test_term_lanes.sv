// test_term_lanes.sv
//
// Terminate en cada una de las 8 lanes: 8 frames, el FD del frame k cae en
// la lane k. Cada posición usa un block type distinto del lado PCS
// (0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF).
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
                for (int k = 0; k < 8; k++) tb_top.u_gen.send_frame(2, k);
                tb_top.u_gen.send_idle(20);
            end
            for (int k = 0; k < 8; k++) tb_top.u_chk.expect_frame(2, k);
        join

        done = 1;
    end

endmodule

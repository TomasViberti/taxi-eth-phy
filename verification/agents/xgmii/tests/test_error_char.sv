// test_error_char.sv
//
// Carácter de error (0xFE) en medio de un frame. El TX
// manda un bloque de error. Del lado XGMII RX tiene que salir el frame hasta
// ese punto y después una palabra de error , es decir, 0xFE en las 8 lanes.
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
                tb_top.u_gen.send_start();
                tb_top.u_gen.send_data(2);
                // dato con 0xFE en lane 3
                tb_top.u_gen.send_word(64'h11223344_FE667788, 8'b0000_1000);
                tb_top.u_gen.send_data(1);
                tb_top.u_gen.send_terminate(4);
                tb_top.u_gen.send_idle(20);
            end
            begin
                tb_top.u_chk.expect_start();
                tb_top.u_chk.expect_data(2);
                tb_top.u_chk.expect_error();
            end
        join

        done = 1;
    end

endmodule

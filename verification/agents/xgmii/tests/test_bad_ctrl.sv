// test_bad_ctrl.sv
//
// Caracteres de control que no existen en la tabla 46-3 (0x55 y 0x00 con el
// bit de control en 1). El TX los codifica como error: del lado XGMII RX tiene
// que salir una palabra de error (0xFE) y tx_bad_block tiene que subir.
// Pasa si error_count == 0.

module test (input logic start, output logic done);

    int bad_blocks = 0;

    // Cuenta los ciclos con tx_bad_block en 1
    always @(posedge tb_top.tx_clk)
        if (tb_top.dut.tx_bad_block) bad_blocks++;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_gen.send_idle(1);
        tb_top.u_gen.send_idle(10);

        // 0x55 con c=1 en las 8 lanes
        fork
            begin
                tb_top.u_gen.send_word({8{8'h55}}, 8'hFF);
                tb_top.u_gen.send_idle(20);
            end
            tb_top.u_chk.expect_error();
        join

        // 0x00 con c=1 en una sola lane (lane 3), el resto idle
        fork
            begin
                tb_top.u_gen.send_word({{4{8'h07}}, 8'h00, {3{8'h07}}}, 8'hFF);
                tb_top.u_gen.send_idle(20);
            end
            tb_top.u_chk.expect_error();
        join

        if (bad_blocks < 2) begin
            tb_top.u_chk.error_count++;
            $display("[%0t] TEST ERROR: tx_bad_block se vio %0d veces, se esperaban 2", $time, bad_blocks);
        end

        done = 1;
    end

endmodule

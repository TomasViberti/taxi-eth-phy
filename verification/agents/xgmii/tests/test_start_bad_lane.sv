// test_start_bad_lane.sv
//
// Start en una lane no permitida (1, 2, 3, 5, 6, 7). Según la norma sólo
// lane 0 o 4. El TX lo marca como error y levanta
// tx_bad_block. Del lado XGMII RX tiene que salir 0xFE
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

        for (int lane = 1; lane < 8; lane++) begin
            if (lane == 4) continue;   // lane 4 es válida
            fork
                begin
                    tb_top.u_gen.send_start_lane(lane);
                    tb_top.u_gen.send_idle(20);
                end
                tb_top.u_chk.expect_error();
            join
        end

        // El TX tiene que haber marcado al menos un bloque malo por cada start
        if (bad_blocks < 6) begin
            tb_top.u_chk.error_count++;
            $display("[%0t] TEST ERROR: tx_bad_block se vio %0d veces, se esperaban 6", $time, bad_blocks);
        end

        done = 1;
    end

endmodule

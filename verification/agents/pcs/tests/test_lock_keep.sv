// test_lock_keep.sv
//
// 15 sync headers inválidos en cada ventana de 64 bloques.
// Norma: block lock se pierde recién con 16
// headers inválidos en una ventana de 64. Con 15 se tiene que mantener.
// Mismo patrón que test_lock_loss.sv: 15 inválidos seguidos + 49
// válidos, repetido. Cualquier ventana de 64 bloques tiene exactamente 15.
// Pasa si rx_block_lock nunca baja.

module test (input logic start, output logic done);

    int lock_lost = 0;
    logic monitor = 1;

    // Loopback XGMII: el RX recibe lo que manda pcs_gen y su salida XGMII vuelve al TX
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        fork
            // Monitor de block lock durante todo el patrón
            while (monitor) begin
                @(posedge tb_top.rx_clk);
                if (!tb_top.dut.rx_block_lock) lock_lost++;
            end
            begin
                repeat (8) begin
                    repeat (7) begin
                        tb_top.u_pcs_gen.send_idle_hdr(2'b00);
                        tb_top.u_pcs_gen.send_idle_hdr(2'b11);
                    end
                    tb_top.u_pcs_gen.send_idle_hdr(2'b00);
                    tb_top.u_pcs_gen.send_idle(49);
                end
                tb_top.u_pcs_gen.send_idle(10);
                monitor = 0;
            end
        join_none
        wait fork;

        if (lock_lost != 0) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: rx_block_lock bajó %0d ciclos con 15 headers inválidos cada 64 bloques", $time, lock_lost);
        end

        done = 1;
    end

endmodule

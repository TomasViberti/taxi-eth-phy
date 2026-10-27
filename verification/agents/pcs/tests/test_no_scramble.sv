// test_no_scramble.sv
//
// Frame mandado sin scramblear.
// Norma: el RX descramblea todo payload, así que un payload sin
// scramblear sale distinto de lo que se mandó. El sync header no se scramblea, así
// que block lock se tiene que mantener.
// Es un test negativo: pasa si el frame NO sale bien y rx_block_lock nunca baja.

module test (input logic start, output logic done);

    int lock_lost = 0;
    int errors_before;

    // Loopback XGMII: el RX recibe lo que manda pcs_gen y su salida XGMII vuelve al TX
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        fork
            // Monitor de block lock durante todo el estímulo
            begin
                repeat (1500) begin
                    @(posedge tb_top.rx_clk);
                    if (!tb_top.dut.rx_block_lock) lock_lost++;
                end
            end
            begin
                tb_top.u_pcs_gen.scramble_en = 0;
                tb_top.u_pcs_gen.send_frame(8, 3);
                tb_top.u_pcs_gen.send_idle(1500);
            end
            begin
                errors_before = tb_top.u_xgmii_chk.error_count;
                tb_top.u_xgmii_chk.expect_frame(8, 3);

                // El checker tenía que encontrar errores: se descuentan y se
                // verifica que existan
                if (tb_top.u_xgmii_chk.error_count == errors_before) begin
                    tb_top.u_xgmii_chk.error_count++;
                    $display("[%0t] TEST ERROR: el frame sin scramblear salió intacto", $time);
                end else begin
                    tb_top.u_xgmii_chk.error_count = errors_before;
                end
            end
        join_none
        wait fork;

        if (lock_lost != 0) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: rx_block_lock bajó %0d ciclos sin headers inválidos", $time, lock_lost);
        end

        done = 1;
    end

endmodule

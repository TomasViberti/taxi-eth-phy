// test_no_scramble.sv
//
// Frame mandado sin scramblear.
// Norma: el RX descramblea todo payload (cl. 49.2.10), así que un payload sin
// scramblear sale distinto de lo que se mandó: el frame no puede salir
// intacto del lado XGMII RX. El sync header no se scramblea (cl. 49.2.6), así
// que block lock se tiene que mantener.
// Es un test negativo: pasa si el checker XGMII no cuenta ningún frame
// correcto y rx_block_lock nunca baja.

module test (input logic start, output logic done);

    int lock_lost = 0;

    // Loopback XGMII: el RX recibe lo que manda pcs_gen y su salida XGMII vuelve al TX
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        // El checker XGMII cuenta desde acá
        tb_top.u_xgmii_chk.clear();

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
        join_none
        // join_none + wait fork en vez de join: ver xgmii/tests/test_happy_path.sv
        wait fork;

        // Salida XGMII del RX: el frame no puede haber salido bien
        if (tb_top.u_xgmii_chk.frame_count != 0) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: el frame sin scramblear salió intacto", $time);
        end

        if (lock_lost != 0) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: rx_block_lock bajó %0d ciclos sin headers inválidos", $time, lock_lost);
        end

        done = 1;
    end

endmodule

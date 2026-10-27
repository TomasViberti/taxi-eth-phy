// test_scramble_hdr.sv
//
// Sync header scrambleado junto con el payload (inválido según norma).
// Norma: el header scrambleado sale 00 o 11 en cerca de la mitad de los
// bloques. Con 16 headers inválidos en una ventana de 64 se pierde block lock.
// Pasa si rx_block_lock baja.

module test (input logic start, output logic done);

    int n;

    // Loopback XGMII: el RX recibe lo que manda pcs_gen y su salida XGMII vuelve al TX
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        tb_top.u_pcs_gen.scramble_hdr = 1;
        n = 0;
        while (tb_top.dut.rx_block_lock && n < 1000) begin
            tb_top.u_pcs_gen.send_idle(1);
            n++;
        end

        if (tb_top.dut.rx_block_lock) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: rx_block_lock no bajó en %0d bloques con header scrambleado", $time, n);
        end

        done = 1;
    end

endmodule

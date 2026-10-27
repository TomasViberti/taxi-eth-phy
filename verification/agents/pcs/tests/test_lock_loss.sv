// test_lock_loss.sv
//
// 16 sync headers inválidos en cada ventana de 64 bloques.
// Norma: con 16 headers inválidos dentro de una ventana de 64 se pierde block lock.
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

        n = 0;
        while (tb_top.dut.rx_block_lock && n < 8) begin
            repeat (8) begin
                tb_top.u_pcs_gen.send_idle_hdr(2'b00);
                tb_top.u_pcs_gen.send_idle_hdr(2'b11);
            end
            tb_top.u_pcs_gen.send_idle(48);
            n++;
        end
        tb_top.u_pcs_gen.send_idle(10);

        if (tb_top.dut.rx_block_lock) begin
            tb_top.u_xgmii_chk.error_count++;
            $display("[%0t] TEST ERROR: rx_block_lock no bajó con 16 headers inválidos cada 64 bloques", $time);
        end

        done = 1;
    end

endmodule

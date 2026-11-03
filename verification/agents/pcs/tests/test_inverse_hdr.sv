// test_inverse_hdr.sv
//
// Sync header inverso: un idle con header de dato (01) y un dato con header
// de control (10).
// Norma (cl. 49.2.13.2.3, recepción):
// - idle con header 01 es de tipo D. D en RX_C -> RX_E: sale la palabra de
//   error (0xFE en las 8 lanes).
// - dato con header 10 dentro del frame: el primer byte se toma como block
//   type. Sea lo que sea, en RX_D termina en RX_E: si es E, C o S va directo,
//   y si es T también, porque el bloque siguiente es un dato (T sólo es
//   válido seguido de C o S). Sale la palabra de error y el frame sigue con
//   los datos. (Con esta PRBS el byte es 0xFF: se lee como T en la posición 7.)
// - Lado XGMII: 2 palabras de error: 16 /E/. El frame no cuenta como correcto.
// Pasa si error_count == 0.

module test (input logic start, output logic done);

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

        tb_top.u_pcs_gen.send_idle_hdr(2'b10);    // header de dato
        tb_top.u_pcs_gen.send_idle(20);

        tb_top.u_pcs_gen.send_start();
        tb_top.u_pcs_gen.send_data(2);
        tb_top.u_pcs_gen.send_data_hdr(2'b01);    // header de control
        tb_top.u_pcs_gen.send_data(2);
        tb_top.u_pcs_gen.send_terminate(3);
        tb_top.u_pcs_gen.send_idle(20);

        // Salida XGMII del RX
        tb_top.u_xgmii_chk.check_counts(.frames(0), .e(16), .prbs(0), .seq(0));

        done = 1;
    end

endmodule

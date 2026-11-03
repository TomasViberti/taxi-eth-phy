// test_start_mismatch.sv
//
// Block type descorrelacionado del contenido: block type 0x78 (start en la
// posición 0) pero con el contenido de un start en la posición 4 (4 /I/,
// 4 bits en 0 y 3 bytes de preámbulo), seguido de datos y terminate.
// Norma (figura 49-7): la posición del start la da sólo el block type. Para
// 0x78 los 7 bytes siguientes son D1-D7, así que el RX tiene que sacarlos como
// dato tal cual: lane 0 = 0xFB, lanes 1-4 = 0x00, lanes 5-7 = 0x55.
// - Lado XGMII: el /S/ sale bien, pero en lane 1 llega el dato 0x00 en vez de
//   preámbulo (cl. 46.2.2): 1 error de secuencia, sin /E/ (el RX no tiene que
//   marcarlo como error, sólo pasa los datos). Ningún frame correcto.
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

        tb_top.u_pcs_gen.send_start({{3{8'h55}}, 4'h0, {4{7'h00}}});
        tb_top.u_pcs_gen.send_data(2);
        tb_top.u_pcs_gen.send_terminate(3);
        tb_top.u_pcs_gen.send_idle(20);

        // Salida XGMII del RX
        tb_top.u_xgmii_chk.check_counts(.frames(0), .e(0), .prbs(0), .seq(1));

        done = 1;
    end

endmodule

// test_bit_flip.sv
//
// Un bit invertido en la línea dentro del dato de un frame, en dos frames.
// Norma (cl. 49.2.10): el descrambler es 1 + x^39 + x^58, así que un bit
// errado en la posición k de la línea sale errado en k, k+39 y k+58: 3 bits
// errados, no 1.
// - frame 1: bit 0 invertido (errores en los bits 0, 39 y 58 del bloque)
// - frame 2: bit 20 invertido (errores en los bits 20 y 59 del bloque y en
//   el bit 14 del bloque siguiente)
// - Lado XGMII: en cada frame el checker PRBS31 detecta el primer bit errado
//   y se deslockea, así que cuenta 1 error de PRBS por frame y ningún frame
//   correcto. Los otros 2 bits errados de cada frame no se ven: el checker ya
//   está deslockeado.
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

        tb_top.u_pcs_gen.send_start();
        tb_top.u_pcs_gen.send_data(2);
        tb_top.u_pcs_gen.send_data_flip(0);
        tb_top.u_pcs_gen.send_data(3);
        tb_top.u_pcs_gen.send_terminate(2);
        tb_top.u_pcs_gen.send_idle(20);

        tb_top.u_pcs_gen.send_start();
        tb_top.u_pcs_gen.send_data(2);
        tb_top.u_pcs_gen.send_data_flip(20);
        tb_top.u_pcs_gen.send_data(3);
        tb_top.u_pcs_gen.send_terminate(2);
        tb_top.u_pcs_gen.send_idle(20);

        // Salida XGMII del RX
        tb_top.u_xgmii_chk.check_counts(.frames(0), .e(0), .prbs(2), .seq(0));

        done = 1;
    end

endmodule

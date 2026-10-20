// prbs.sv
//
// Generador de secuencia PRBS (LFSR), usado como fuente de datos del payload.
// También se incluye el scrambleo y descrambleo.

module prbs;

    logic [30:0] prbs_reg  = '1;   // S0..S30
    logic [57:0] scr_reg   = '1;   // S0..S57
    logic [57:0] descr_reg = '1;   // S0..S57

    // PRBS31 con polinomio 1 + x^28 + x^31.
    // Realimentación: S27 xor S30. La salida va invertida
    task generate_prbs(output logic [63:0] data_out);
        logic fb;
        // Bucle del largo de la palabra
        for (int i = 0; i < 64; i++) begin

            // XOR
            fb          = prbs_reg[27] ^ prbs_reg[30];
            // Inversión de la salida
            data_out[i] = ~fb; 

            prbs_reg    = {prbs_reg[29:0], fb};
        end
    endtask

    // Scrambler con polinomio 1 + x^39 + x^58
    task scramble(input logic [63:0] data_in, output logic [63:0] data_out);
        for (int i = 0; i < 64; i++) begin
            data_out[i] = data_in[i] ^ scr_reg[38] ^ scr_reg[57];
            scr_reg     = {scr_reg[56:0], data_out[i]};
        end
    endtask

    // Descrambler
    task descramble(input logic [63:0] data_in, output logic [63:0] data_out);
        for (int i = 0; i < 64; i++) begin
            data_out[i] = data_in[i] ^ descr_reg[38] ^ descr_reg[57];
            descr_reg   = {descr_reg[56:0], data_in[i]};
        end
    endtask

endmodule

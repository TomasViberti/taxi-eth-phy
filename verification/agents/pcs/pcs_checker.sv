// pcs_checker.sv
//
// Checker PCS 10GBASE-R.
//
// - El descrambler (cl. 49.2.10) corre en todos los ciclos.
// - Cada task lee un bloque descrambleado, arma el esperado y los compara (header y payload).
// - El payload esperado sale de su propia instancia de prbs, con la misma
//   semilla que el generador XGMII.
// - Cada diferencia suma 1 a error_count. El test mira error_count al final.

module pcs_checker (pcs_if p_if);

    // Sync header. Bit 0 = primer bit transmitido:
    // "01" dato, "10" control
    localparam logic [1:0] SYNC_DATA = 2'b10;
    localparam logic [1:0] SYNC_CTRL = 2'b01;

    // Block types 
    localparam logic [7:0] BT_CTRL    = 8'h1E;
    localparam logic [7:0] BT_START_0 = 8'h78;
    localparam logic [7:0] BT_START_4 = 8'h33;
    
    // Terminate con el T en la posición k: BT_TERM[k]
    localparam logic [7:0] BT_TERM [8] = '{8'h87, 8'h99, 8'hAA, 8'hB4,
                                           8'hCC, 8'hD2, 8'hE1, 8'hFF};

    // Códigos de control de 7 bits (tabla 49-1)
    localparam logic [6:0] C_IDLE  = 7'h00;
    localparam logic [6:0] C_ERROR = 7'h1E;

    // Preámbulo y SFD
    localparam logic [7:0] PRE = 8'h55;
    localparam logic [7:0] SFD = 8'hD5;

    // Máximo de bloques que se espera al start antes de dar error
    localparam int START_TIMEOUT = 1000;

    // Predicción del payload y descrambler
    prbs u_prbs ();

    int error_count = 0;

    // Último bloque recibido, ya descrambleado
    logic [1:0]  blk_header;
    logic [63:0] blk_data;

    // Descrambleo continuo. El resultado queda registrado: recv_block lo lee
    // en el flanco siguiente
    always @(posedge p_if.clk) begin : descramble
        logic [63:0] d;
        u_prbs.descramble(p_if.data, d);
        blk_header <= p_if.header;
        blk_data   <= d;
    end

    // Lee el próximo bloque descrambleado
    task recv_block(output logic [1:0] header, output logic [63:0] data);
        @(posedge p_if.clk);
        header = blk_header;
        data   = blk_data;
    endtask

    // Compara el bloque recibido con el esperado. Si no coinciden, suma un error
    task compare(input string what,
                 input logic [1:0] exp_h, input logic [63:0] exp_d,
                 input logic [1:0] h,     input logic [63:0] d);
        if (h !== exp_h || d !== exp_d) begin
            error_count++;
            $display("[%0t] PCS CHECKER ERROR en %s", $time, what);
            $display("    esperado: header=%b data=%h", exp_h, exp_d);
            $display("    recibido: header=%b data=%h", h, d);
        end
    endtask

    // n bloques de idle
    task expect_idle(input int n);
        logic [1:0]  h;
        logic [63:0] d;
        repeat (n) begin
            recv_block(h, d);
            compare("idle", SYNC_CTRL, {{8{C_IDLE}}, BT_CTRL}, h, d);
        end
    endtask

    // El próximo bloque tiene que ser un bloque de error: 0x1E con 8 /E/
    task expect_error_block();
        logic [1:0]  h;
        logic [63:0] d;
        recv_block(h, d);
        compare("error block", SYNC_CTRL, {{8{C_ERROR}}, BT_CTRL}, h, d);
    endtask

    // Espera hasta que aparezca un bloque 0x1E con algún /E/ y verifica que
    // sea el bloque de error completo (8 /E/). Para errores entre idles, donde
    // no hay un start para alinearse.
    task wait_error_block();
        logic [1:0]  h;
        logic [63:0] d;
        logic        found;
        int n;

        n = 0;
        found = 0;
        while (!found) begin
            recv_block(h, d);
            if (h == SYNC_CTRL && d[7:0] == BT_CTRL)
                for (int pos = 0; pos < 8; pos++)
                    if (d[8+7*pos +: 7] == C_ERROR) found = 1;

            n++;
            if (!found && n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] PCS CHECKER ERROR: no llegó el bloque de error en %0d bloques", $time, n);
                return;
            end
        end

        compare("error block", SYNC_CTRL, {{8{C_ERROR}}, BT_CTRL}, h, d);
    endtask

    // Espera hasta que aparezca un bloque de start (0x78) y verifica el
    // preámbulo y el SFD
    task expect_start();
        logic [1:0]  h;
        logic [63:0] d;
        int n;

        n = 0;
        recv_block(h, d);
        while (!(h == SYNC_CTRL && d[7:0] == BT_START_0)) begin
            n++;
            if (n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] PCS CHECKER ERROR: no llegó el start en %0d bloques", $time, n);
                return;
            end
            recv_block(h, d);
        end

        compare("start", SYNC_CTRL, {SFD, {6{PRE}}, BT_START_0}, h, d);
    endtask

    // n bloques de dato: tienen que coincidir con la PRBS
    task expect_data(input int n);
        logic [63:0] data;
        logic [1:0]  h;
        logic [63:0] d;
        repeat (n) begin
            u_prbs.generate_prbs(data);
            recv_block(h, d);
            compare("data", SYNC_DATA, data, h, d);
        end
    endtask

    // Último bloque del frame: block type según la posición del T, n_bytes de
    // dato y el resto en 0. Se arma igual que en pcs_gen.
    task expect_terminate(input int n_bytes);
        logic [63:0] data;
        logic [63:0] exp_d;
        logic [1:0]  h;
        logic [63:0] d;

        u_prbs.generate_prbs(data);

        exp_d = '0;
        exp_d[7:0] = BT_TERM[n_bytes];
        for (int i = 0; i < n_bytes; i++)
            exp_d[8*(i+1) +: 8] = data[8*i +: 8];

        recv_block(h, d);
        compare("terminate", SYNC_CTRL, exp_d, h, d);
    endtask

    // Frame completo: start, n_words de dato y terminate
    task expect_frame(input int n_words, input int n_bytes);
        expect_start();
        expect_data(n_words);
        expect_terminate(n_bytes);
    endtask

    // Espejo de send_frame_lane4: start 0x33, datos corridos 4 bytes y T en la
    // posición 4
    task expect_frame_lane4(input int n_words);
        logic [63:0] data;
        logic [31:0] carry;
        logic [63:0] exp_d;
        logic [1:0]  h;
        logic [63:0] d;
        int n;

        // Espera el start en la posición 4
        n = 0;
        recv_block(h, d);
        while (!(h == SYNC_CTRL && d[7:0] == BT_START_4)) begin
            n++;
            if (n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] PCS CHECKER ERROR: no llegó el start 0x33 en %0d bloques", $time, n);
                return;
            end
            recv_block(h, d);
        end
        compare("start lane 4", SYNC_CTRL, {{3{PRE}}, 4'h0, {4{C_IDLE}}, BT_START_4}, h, d);
        carry = {SFD, {3{PRE}}};

        repeat (n_words) begin
            u_prbs.generate_prbs(data);
            recv_block(h, d);
            compare("data lane 4", SYNC_DATA, {data[31:0], carry}, h, d);
            carry = data[63:32];
        end

        exp_d = '0;
        exp_d[7:0]  = BT_TERM[4];
        exp_d[39:8] = carry;
        recv_block(h, d);
        compare("terminate lane 4", SYNC_CTRL, exp_d, h, d);
    endtask

endmodule

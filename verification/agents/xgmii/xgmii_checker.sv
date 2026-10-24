// xgmii_checker.sv
//
// Checker XGMII.
//
// Requisito: tiene que funcionar junto con xgmii_gen o solo (por ejemplo,
// mirando la salida XGMII cuando el estímulo viene de pcs_gen). Por eso el
// checker sólo mira la interface XGMII y no recibe nada del generador.
//
// Planteo elegido: tasks inversas a las del generador.
//
// generador                          checker
// send_word(d, c)               ->   recv_word(d, c)
// send_idle(n)                  ->   expect_idle(n)
// send_start()                  ->   expect_start()
// send_data(n)                  ->   expect_data(n)
// send_terminate(n_bytes)       ->   expect_terminate(n_bytes)
// send_frame(n_words, n_bytes)  ->   expect_frame(n_words, n_bytes)
//
// - Cada task lee una palabra, arma la palabra esperada y las compara.
// - El payload esperado sale de su propia instancia de prbs, con la misma
//   semilla que el generador: así predice los mismos datos sin hablar con él.
// - Cada diferencia suma 1 a error_count. El test mira error_count al final.
// - recv_word es la única task que lee de la interface.

module xgmii_checker (xgmii_if x_if);

    // Caracteres de control (tabla 46-3)
    localparam logic [7:0] IDLE  = 8'h07;
    localparam logic [7:0] START = 8'hFB;
    localparam logic [7:0] TERM  = 8'hFD;
    localparam logic [7:0] ERROR = 8'hFE;

    // Preámbulo y SFD
    localparam logic [7:0] PRE = 8'h55;
    localparam logic [7:0] SFD = 8'hD5;

    // Máximo de palabras que expect_start espera al start antes de dar error
    localparam int START_TIMEOUT = 1000;

    // Predicción del payload
    prbs u_prbs ();

    int error_count = 0;

    // Lee la palabra presente en la interface en el próximo flanco
    task recv_word(output logic [63:0] d, output logic [7:0] c);
        @(posedge x_if.clk);
        d = x_if.data;
        c = x_if.control;
    endtask

    // Compara la palabra recibida con la esperada. Si no coinciden, suma un error
    task compare(input string what,
                 input logic [63:0] exp_d, input logic [7:0] exp_c,
                 input logic [63:0] d,     input logic [7:0] c);
        if (d !== exp_d || c !== exp_c) begin
            error_count++;
            $display("[%0t] XGMII CHECKER ERROR en %s", $time, what);
            $display("    esperado: c=%b d=%h", exp_c, exp_d);
            $display("    recibido: c=%b d=%h", c, d);
        end
    endtask

    // n palabras de idle
    task expect_idle(input int n);
        logic [63:0] d;
        logic [7:0]  c;
        repeat (n) begin
            recv_word(d, c);
            compare("idle", {8{IDLE}}, 8'hFF, d, c);
        end
    endtask

    // Espera hasta que aparezca el start en lane 0 y verifica las lanes 1-7
    // (por defecto preámbulo y SFD).
    task expect_start(input logic [55:0] content = {SFD, {6{PRE}}});
        logic [63:0] d;
        logic [7:0]  c;
        int n;

        n = 0;
        recv_word(d, c);
        while (!(c[0] && d[7:0] == START)) begin
            n++;
            if (n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] XGMII CHECKER ERROR: no llegó el start en %0d palabras", $time, n);
                return;
            end
            recv_word(d, c);
        end

        compare("start", {content, START}, 8'h01, d, c);
    endtask

    // n palabras de dato: tienen que coincidir con la PRBS
    task expect_data(input int n);
        logic [63:0] data;
        logic [63:0] d;
        logic [7:0]  c;
        repeat (n) begin
            u_prbs.generate_prbs(data);
            recv_word(d, c);
            compare("data", data, 8'h00, d, c);
        end
    endtask

    // Una palabra de dato con los bits de mask invertidos respecto de la PRBS
    // (errores esperados en la línea)
    task expect_data_mask(input logic [63:0] mask);
        logic [63:0] data;
        logic [63:0] d;
        logic [7:0]  c;
        u_prbs.generate_prbs(data);
        recv_word(d, c);
        compare("data mask", data ^ mask, 8'h00, d, c);
    endtask

    // Avanza la PRBS n palabras sin leer la interface. Para cuando el
    // generador mandó datos de la PRBS que el DUT tiene que reemplazar por
    // error: así el checker sigue alineado con el generador.
    task skip_data(input int n);
        logic [63:0] data;
        repeat (n) u_prbs.generate_prbs(data);
    endtask

    // Última palabra del frame: n_bytes de dato, el FD en la lane n_bytes y el
    // resto idle. Se arma igual que en el generador.
    task expect_terminate(input int n_bytes);
        logic [63:0] data;
        logic [63:0] exp_d;
        logic [7:0]  exp_c;
        logic [63:0] d;
        logic [7:0]  c;

        u_prbs.generate_prbs(data);

        for (int lane = 0; lane < 8; lane++) begin
            if (lane < n_bytes) begin
                exp_d[8*lane +: 8] = data[8*lane +: 8];
                exp_c[lane]        = 1'b0;
            end else if (lane == n_bytes) begin
                exp_d[8*lane +: 8] = TERM;
                exp_c[lane]        = 1'b1;
            end else begin
                exp_d[8*lane +: 8] = IDLE;
                exp_c[lane]        = 1'b1;
            end
        end

        recv_word(d, c);
        compare("terminate", exp_d, exp_c, d, c);
    endtask

    // Frame completo: start, n_words de dato y terminate.
    task expect_frame(input int n_words, input int n_bytes);
        expect_start();
        expect_data(n_words);
        expect_terminate(n_bytes);
    endtask

    // Espejo de send_frame_lane4: frame con start en lane 4, corrido 4 bytes
    task expect_frame_lane4(input int n_words);
        logic [63:0] data;
        logic [31:0] carry;
        logic [63:0] d;
        logic [7:0]  c;
        int n;

        // Espera el start en lane 4
        n = 0;
        recv_word(d, c);
        while (!(c[4] && d[39:32] == START)) begin
            n++;
            if (n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] XGMII CHECKER ERROR: no llegó el start en lane 4 en %0d palabras", $time, n);
                return;
            end
            recv_word(d, c);
        end
        compare("start lane 4", {{3{PRE}}, START, {4{IDLE}}}, 8'h1F, d, c);
        carry = {SFD, {3{PRE}}};

        repeat (n_words) begin
            u_prbs.generate_prbs(data);
            recv_word(d, c);
            compare("data lane 4", {data[31:0], carry}, 8'h00, d, c);
            carry = data[63:32];
        end

        recv_word(d, c);
        compare("terminate lane 4", {{3{IDLE}}, TERM, carry}, 8'hF0, d, c);
    endtask

    // La próxima palabra tiene que ser un bloque de error completo: 0xFE en las
    // 8 lanes (EBLOCK_T del TX, cl. 49.2.13.2.3)
    task expect_error_word();
        logic [63:0] d;
        logic [7:0]  c;
        recv_word(d, c);
        compare("error word", {8{ERROR}}, 8'hFF, d, c);
    endtask

    // Espera hasta que aparezca una palabra con algún 0xFE (con c=1) y verifica
    // que sea la palabra de error completa (0xFE en las 8 lanes). Para errores
    // entre idles, donde no hay un start para alinearse.
    task wait_error_word();
        logic [63:0] d;
        logic [7:0]  c;
        logic        found;
        int n;

        n = 0;
        found = 0;
        while (!found) begin
            recv_word(d, c);
            for (int lane = 0; lane < 8; lane++)
                if (c[lane] && d[8*lane +: 8] == ERROR) found = 1;

            n++;
            if (!found && n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] XGMII CHECKER ERROR: no llegó la palabra de error en %0d palabras", $time, n);
                return;
            end
        end

        compare("error word", {8{ERROR}}, 8'hFF, d, c);
    endtask

    // Espera hasta que aparezca una palabra con 0xFE (con c=1) en alguna lane.
    // Según lo que mandó el generador, el error sale distinto:
    // - palabra que mezcla datos y controles de forma inválida: el TX la
    //   reemplaza entera por un bloque de error -> 0xFE en las 8 lanes.
    // - palabra toda de control con un carácter inválido: el TX codifica
    //   sólo esa lane como /E/ -> 0xFE sólo en esa lane.
    task expect_error();
        logic [63:0] d;
        logic [7:0]  c;
        logic        found;
        int n;

        n = 0;
        found = 0;
        while (!found) begin
            recv_word(d, c);
            for (int lane = 0; lane < 8; lane++)
                if (c[lane] && d[8*lane +: 8] == ERROR) found = 1;

            n++;
            if (!found && n == START_TIMEOUT) begin
                error_count++;
                $display("[%0t] XGMII CHECKER ERROR: no llegó la palabra de error en %0d palabras", $time, n);
                return;
            end
        end
    endtask

endmodule

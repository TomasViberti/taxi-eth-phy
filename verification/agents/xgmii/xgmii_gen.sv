// xgmii_gen.sv
//
// Generador XGMII basado en tasks.
//
// Idea:
// - Cada task de bajo nivel hace una cosa que define la norma.
// - Las tasks de alto nivel arman un frame completo llamando a las de bajo nivel.
// - Las tasks de inyección de errores rompen la norma a propósito, para los
//   tests que verifican cómo responde el DUT.
// - Un test es una secuencia de llamadas a estas tasks.
// - El generador sólo escribe en xgmii_if. No sabe si hay un checker ni cuál.
// - send_word es la única task que escribe en la interface.

module xgmii_gen (xgmii_if x_if);

    // Caracteres de control (tabla 46-3)
    localparam logic [7:0] IDLE  = 8'h07;
    localparam logic [7:0] START = 8'hFB;
    localparam logic [7:0] TERM  = 8'hFD;
    localparam logic [7:0] ERROR = 8'hFE;

    // Preámbulo y SFD
    localparam logic [7:0] PRE = 8'h55;
    localparam logic [7:0] SFD = 8'hD5;

    // Fuente del payload
    prbs u_prbs ();

    // La línea arranca en idle
    initial begin
     x_if.data = {8{IDLE}};
     x_if.control = 8'hFF;
    end

    // Escribe una palabra en la interface en el próximo flanco
    task send_word(input logic [63:0] d, input logic [7:0] c);
        @(posedge x_if.clk);
     x_if.data <= d;
     x_if.control <= c;
    endtask

    // n palabras de idle
    task send_idle(input int n);
        repeat (n) send_word({8{IDLE}}, 8'hFF);
    endtask

    // Start en lane 0 + 6 bytes de preámbulo + SFD
    task send_start();
        send_word({SFD, {6{PRE}}, START}, 8'h01);
    endtask

    // n palabras de dato desde la PRBS
    task send_data(input int n);
        logic [63:0] data;
        repeat (n) begin
            u_prbs.generate_prbs(data);
            send_word(data, 8'h00);
        end
    endtask

    // Última palabra del frame: n_bytes de dato (0 a 7), el FD y el resto idle.
    // El FD cae en la lane n_bytes.
    task send_terminate(input int n_bytes);
        logic [63:0] data;
        logic [63:0] d;
        logic [7:0]  c;

        u_prbs.generate_prbs(data);

        for (int lane = 0; lane < 8; lane++) begin
            if (lane < n_bytes) begin
                d[8*lane +: 8] = data[8*lane +: 8];
                c[lane]        = 1'b0;
            end else if (lane == n_bytes) begin
                d[8*lane +: 8] = TERM;
                c[lane]        = 1'b1;
            end else begin
                d[8*lane +: 8] = IDLE;
                c[lane]        = 1'b1;
            end
        end

        send_word(d, c);
    endtask

    // Frame completo: start, n_words de dato, terminate y ipg palabras de idle
    task send_frame(input int n_words, input int n_bytes, input int ipg = 2);
        send_start();
        send_data(n_words);
        send_terminate(n_bytes);
        send_idle(ipg);
    endtask

    // Frame con el start en lane 4 (válido en 64 bits: es la lane (bloque) 0 de la
    // segunda palabra de 32). Todo el frame queda corrido 4 bytes: la mitad
    // alta de cada palabra PRBS pasa a la mitad baja de la palabra siguiente.
    // El FD cae en lane 4 de la última palabra.
    task send_frame_lane4(input int n_words, input int ipg = 2);
        logic [63:0] data;
        logic [31:0] carry;

        // lanes 0-3 idle, start en lane 4, preámbulo en lanes 5-7
        send_word({{3{PRE}}, START, {4{IDLE}}}, 8'h1F);
        // el resto del preámbulo y el SFD van en la palabra siguiente
        carry = {SFD, {3{PRE}}};

        repeat (n_words) begin
            u_prbs.generate_prbs(data);
            send_word({data[31:0], carry}, 8'h00);
            carry = data[63:32];
        end

        // últimos 4 bytes de dato, FD en lane 4, idle
        send_word({{3{IDLE}}, TERM, carry}, 8'hF0);
        send_idle(ipg);
    endtask

    
    
    //-------------------------------------------------------------------
    // Inyección de errores
    // (send_word sirve para mandar cualquier palabra, válida o no)

    // Palabra con el start en cualquier lane (bloque): idle antes, FB en la lane,
    // preámbulo después. Sólo lane 0 y 4 son válidas.
    task send_start_lane(input int lane);
        logic [63:0] d;
        logic [7:0]  c;

        for (int l = 0; l < 8; l++) begin
            if (l < lane) begin
                d[8*l +: 8] = IDLE;
                c[l]        = 1'b1;
            end else if (l == lane) begin
                d[8*l +: 8] = START;
                c[l]        = 1'b1;
            end else begin
                d[8*l +: 8] = PRE;
                c[l]        = 1'b0;
            end
        end

        send_word(d, c);
    endtask

endmodule

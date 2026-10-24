// pcs_gen.sv
//
// Generador PCS 10GBASE-R basado en tasks.
//
// - Arma bloques 64B/66B según la norma, los
//   scramblea y los escribe en pcs_if.
// - Las tasks de alto nivel arman un frame completo con las de bajo nivel.
// - Las tasks de inyección de errores rompen la norma a propósito.
// - La línea se escribe en todos los ciclos: si ninguna task mandó un bloque,
//   sale un idle scrambleado (como un transmisor real).

module pcs_gen (pcs_if p_if);

    // Sync header. Bit 0 = primer bit transmitido: "01" (dato), "10" (control)
    localparam logic [1:0] SYNC_DATA = 2'b10;
    localparam logic [1:0] SYNC_CTRL = 2'b01;

    // Block types (figura 49-7)
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

    // Fuente del payload y scrambler
    prbs u_prbs ();

    // Inyección de errores (los cambia el test)
    logic scramble_en  = 1;   // 0: payload sin scramblear
    logic scramble_hdr = 0;   // 1: scramblea también el sync header

    // La línea arranca en idle
    initial begin
        p_if.header = SYNC_CTRL;
        p_if.data   = {{8{C_IDLE}}, BT_CTRL};
    end

    // Bloques pendientes de mandar: {flip, header, data}
    logic [129:0] queue [$];

    // Escritura continua de la línea: en cada flanco scramblea y manda el
    // próximo bloque de la cola, o un idle si no hay ninguno. Así la línea
    // nunca queda con un bloque repetido, que el RX descramblearía como basura.
    // flip se aplica después del scrambler (error en la línea).
    always @(posedge p_if.clk) begin : drive
        logic [129:0] blk;
        logic [63:0]  flip;
        logic [1:0]   h;
        logic [63:0]  d;

        if (queue.size() != 0) begin
            blk  = queue.pop_front();
            flip = blk[129:66];
            h    = blk[65:64];
            d    = blk[63:0];
        end else begin
            flip = '0;
            h    = SYNC_CTRL;
            d    = {{8{C_IDLE}}, BT_CTRL};
        end

        if (scramble_en) begin
            if (scramble_hdr) u_prbs.scramble_hdr(h, h);
            u_prbs.scramble(d, d);
        end

        p_if.header <= h;
        p_if.data   <= d ^ flip;
    end

    // Encola un bloque y espera un flanco: un bloque por ciclo
    task send_block(input logic [1:0] header, input logic [63:0] data,
                    input logic [63:0] flip = '0);
        queue.push_back({flip, header, data});
        @(posedge p_if.clk);
    endtask

    // n bloques de idle: block type 0x1E con 8 /I/
    task send_idle(input int n);
        repeat (n) send_block(SYNC_CTRL, {{8{C_IDLE}}, BT_CTRL});
    endtask

    // Bloque de error: block type 0x1E con 8 /E/
    task send_error();
        send_block(SYNC_CTRL, {{8{C_ERROR}}, BT_CTRL});
    endtask

    // Start en la posición 0: block type 0x78 + D1-D7 (por defecto 6 bytes de
    // preámbulo + SFD)
    task send_start(input logic [55:0] content = {SFD, {6{PRE}}});
        send_block(SYNC_CTRL, {content, BT_START_0});
    endtask

    // n bloques de dato desde la PRBS
    task send_data(input int n);
        logic [63:0] data;
        repeat (n) begin
            u_prbs.generate_prbs(data);
            send_block(SYNC_DATA, data);
        end
    endtask

    // Último bloque del frame: T en la posición n_bytes (0 a 7), con n_bytes
    // de dato antes. Lo que queda después de los datos son los bits en 0 del
    // T y los /I/.
    task send_terminate(input int n_bytes);
        logic [63:0] data;
        logic [63:0] d;

        u_prbs.generate_prbs(data);

        d = '0;
        d[7:0] = BT_TERM[n_bytes];
        for (int i = 0; i < n_bytes; i++)
            d[8*(i+1) +: 8] = data[8*i +: 8];

        send_block(SYNC_CTRL, d);
    endtask

    // Frame completo: start, n_words de dato, terminate y ipg bloques de idle
    task send_frame(input int n_words, input int n_bytes, input int ipg = 2);
        send_start();
        send_data(n_words);
        send_terminate(n_bytes);
        send_idle(ipg);
    endtask

    // Frame con el start en la posición 4 (block type 0x33): 4 /I/, 4 bits en
    // 0 y 3 bytes de preámbulo. Todo el frame queda corrido 4 bytes, igual que
    // send_frame_lane4 del lado XGMII. Termina con el T en la posición 4.
    task send_frame_lane4(input int n_words, input int ipg = 2);
        logic [63:0] data;
        logic [31:0] carry;
        logic [63:0] d;

        send_block(SYNC_CTRL, {{3{PRE}}, 4'h0, {4{C_IDLE}}, BT_START_4});
        carry = {SFD, {3{PRE}}};

        repeat (n_words) begin
            u_prbs.generate_prbs(data);
            send_block(SYNC_DATA, {data[31:0], carry});
            carry = data[63:32];
        end

        d = '0;
        d[7:0]  = BT_TERM[4];
        d[39:8] = carry;
        send_block(SYNC_CTRL, d);
        send_idle(ipg);
    endtask




    //--------------------------Inyección de errores---------------------------

    // (send_block sirve para mandar cualquier bloque, válido o no)
    
    // Bloque de idle con un sync header cualquiera (00 y 11 son inválidos)
    task send_idle_hdr(input logic [1:0] header);
        send_block(header, {{8{C_IDLE}}, BT_CTRL});
    endtask

    // Un bloque de dato de la PRBS con un sync header cualquiera
    task send_data_hdr(input logic [1:0] header);
        logic [63:0] data;
        u_prbs.generate_prbs(data);
        send_block(header, data);
    endtask

    // Bloque de control 0x1E con 8 /I/ salvo el código code en la posición pos
    task send_ctrl_code(input int pos, input logic [6:0] code);
        logic [63:0] d;
        d = {{8{C_IDLE}}, BT_CTRL};
        d[8+7*pos +: 7] = code;
        send_block(SYNC_CTRL, d);
    endtask

    // Bloque de control de 8 /I/ con un block type cualquiera
    task send_block_type(input logic [7:0] bt);
        send_block(SYNC_CTRL, {{8{C_IDLE}}, bt});
    endtask

    // Un bloque de dato de la PRBS con el bit bit_idx invertido en la línea
    task send_data_flip(input int bit_idx);
        logic [63:0] data;
        logic [63:0] flip;

        u_prbs.generate_prbs(data);
        flip = '0;
        flip[bit_idx] = 1'b1;
        send_block(SYNC_DATA, data, flip);
    endtask

endmodule

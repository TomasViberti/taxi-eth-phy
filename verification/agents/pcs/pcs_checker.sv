// pcs_checker.sv
//
// Checker PCS 10GBASE-R

module pcs_checker (
    input logic        clk,
    input logic [63:0] tx_data,   // payload del bloque, scrambleado
    input logic [1:0]  tx_hdr     // sync header, sin scramblear
);

    // Sync header. Bit 0 = primer bit transmitido:
    // "01" dato, "10" control
    localparam logic [1:0] SYNC_DATA = 2'b10;
    localparam logic [1:0] SYNC_CTRL = 2'b01;

    // Block types (figura 49-7)
    localparam logic [7:0] BT_CTRL    = 8'h1E;
    localparam logic [7:0] BT_START_4 = 8'h33;
    localparam logic [7:0] BT_START_0 = 8'h78;

    // Terminate con el T en la posición k: BT_TERM[k]
    localparam logic [7:0] BT_TERM [8] = '{8'h87, 8'h99, 8'hAA, 8'hB4,
                                           8'hCC, 8'hD2, 8'hE1, 8'hFF};

    // Códigos de control de 7 bits (tabla 49-1)
    localparam logic [6:0] C_IDLE  = 7'h00;
    localparam logic [6:0] C_ERROR = 7'h1E;

    // Caracteres XGMII para la palabra decodificada
    localparam logic [7:0] IDLE  = 8'h07;
    localparam logic [7:0] START = 8'hFB;
    localparam logic [7:0] TERM  = 8'hFD;
    localparam logic [7:0] ERROR = 8'hFE;

    // Descrambler
    prbs u_prbs ();

    // Bloques inválidos según la cl. 49.2.4.6, desde el último clear()
    int blk_err_count = 0;

    // Contadores que no dieron lo que esperaba el test. Lo lee Python
    int error_count = 0;

    // Palabra XGMII que representa el último bloque (figura 49-7)
    logic [63:0] dec_data = {8{IDLE}};
    logic [7:0]  dec_ctrl = 8'hFF;

    xgmii_checker #(.NAME("PCS")) u_frame_chk (
        .clk (clk),
        .rxd (dec_data),
        .rxc (dec_ctrl)
    );

    // En cada flanco: descramblea, valida y decodifica el bloque
    always @(posedge clk) begin : monitor
        logic [63:0] block;
        logic [63:0] word_data;
        logic [7:0]  word_ctrl;
        logic        valid;
        string       why;

        u_prbs.descramble(tx_data, block);
        decode_block(tx_hdr, block, word_data, word_ctrl, valid, why);

        // Bloque inválido: se cuenta y pasa como 8 /E/, que es lo que saca un
        // receptor de la norma (EBLOCK_R, cl. 49.2.13.2.3)
        if (!valid) begin
            blk_err_count++;
            $display("[%0t] PCS CHECKER: bloque inválido hdr=%b block=%h, %s",
                     $time, tx_hdr, block, why);
            word_data = {8{ERROR}};
            word_ctrl = 8'hFF;
        end

        dec_data <= word_data;
        dec_ctrl <= word_ctrl;
    end

    // Un código de control de 7 bits (C0..C7) pasado a su carácter XGMII
    // (tabla 49-1). Sólo /I/ y /E/: el resto no se usa
    task decode_code(input logic [6:0] code, output logic [7:0] octet, output logic valid);
        valid = 1;
        case (code)
            C_IDLE:  octet = IDLE;
            C_ERROR: octet = ERROR;
            default: begin
                octet = ERROR;
                valid = 0;
            end
        endcase
    endtask

    // Un bloque descrambleado pasado a la palabra XGMII que representa
    // (figura 49-7). valid = 0 si el bloque es inválido
    task decode_block(input  logic [1:0]  hdr,
                      input  logic [63:0] block,
                      output logic [63:0] word_data,
                      output logic [7:0]  word_ctrl,
                      output logic        valid,
                      output string       why);
        logic [7:0] block_type;
        logic       code_ok;
        int         term_lane;
        int         pos;

        valid      = 1;
        why        = "";
        word_data  = {8{IDLE}};
        word_ctrl  = 8'hFF;
        block_type = block[7:0];

        // Bloque de dato: los 8 bytes son D0..D7 tal cual
        if (hdr == SYNC_DATA) begin
            word_data = block;
            word_ctrl = 8'h00;
            return;
        end

        // Sync header 00 o 11: inválido (cl. 49.2.4.6 a)
        if (hdr != SYNC_CTRL) begin
            valid = 0;
            why   = "sync header 00 u 11";
            return;
        end

        // Block type de terminate: en qué lane cae el /T/
        term_lane = -1;
        for (int k = 0; k < 8; k++)
            if (block_type == BT_TERM[k]) term_lane = k;

        // Bloque de control: block type 0x1E + C0..C7, 7 bits cada uno
        if (block_type == BT_CTRL) begin
            for (int lane = 0; lane < 8; lane++) begin
                decode_code(block[8 + 7*lane +: 7], word_data[8*lane +: 8], code_ok);
                if (!code_ok) begin
                    valid = 0;
                    why   = "código de control que no está en la tabla 49-1";
                end
            end

        // Start en lane 0: block type 0x78 + D1..D7 (S0 implícito)
        end else if (block_type == BT_START_0) begin
            word_data = {block[63:8], START};
            word_ctrl = 8'h01;

        // Start en lane 4: block type 0x33 + C0..C3 + 4 bits en 0 + D5..D7
        // (S4 implícito)
        end else if (block_type == BT_START_4) begin
            for (int lane = 0; lane < 4; lane++) begin
                decode_code(block[8 + 7*lane +: 7], word_data[8*lane +: 8], code_ok);
                if (!code_ok) begin
                    valid = 0;
                    why   = "código de control que no está en la tabla 49-1";
                end
            end
            if (block[39:36] != 4'h0) begin
                valid = 0;
                why   = "bits sin usar distintos de 0 (se mandan en 0, figura 49-7)";
            end
            word_data[39:32] = START;
            word_data[63:40] = block[63:40];
            word_ctrl        = 8'h1F;

        // Terminate en la lane k: block type + D0..D(k-1) + (7-k) bits en 0 +
        // C(k+1)..C7 (T implícito)
        end else if (term_lane >= 0) begin
            for (int lane = 0; lane < term_lane; lane++) begin
                word_data[8*lane +: 8] = block[8 + 8*lane +: 8];
                word_ctrl[lane]        = 1'b0;
            end
            word_data[8*term_lane +: 8] = TERM;

            // Bits sin usar después de los datos
            pos = 8 + 8*term_lane;
            for (int i = 0; i < 7 - term_lane; i++)
                if (block[pos + i] != 1'b0) begin
                    valid = 0;
                    why   = "bits sin usar distintos de 0 (se mandan en 0, figura 49-7)";
                end

            // Códigos de control después del /T/
            pos = pos + (7 - term_lane);
            for (int lane = term_lane + 1; lane < 8; lane++) begin
                decode_code(block[pos +: 7], word_data[8*lane +: 8], code_ok);
                if (!code_ok) begin
                    valid = 0;
                    why   = "código de control que no está en la tabla 49-1";
                end
                pos = pos + 7;
            end

        // Cualquier otro block type: reservado o no usado acá (cl. 49.2.4.6 b)
        end else begin
            valid = 0;
            why   = "block type reservado";
        end
    endtask

    // Pone los contadores en 0, los propios y los de la FSM de frame
    task clear();
        blk_err_count = 0;
        u_frame_chk.clear();
    endtask

    // Compara lo que vio el checker con lo que dice la norma que tiene que
    // salir. Cada contador que no coincide suma 1 a error_count
    task check_counts(input int frames, input int e, input int prbs, input int seq,
                      input int blk = 0);
        $display("[%0t] PCS CHECKER: frames=%0d e=%0d prbs=%0d seq=%0d unlocks=%0d blk=%0d",
                 $time, u_frame_chk.frame_count, u_frame_chk.e_count,
                 u_frame_chk.prbs_err_count, u_frame_chk.seq_err_count,
                 u_frame_chk.unlock_count, blk_err_count);
        check_one("frames", u_frame_chk.frame_count,    frames);
        check_one("e",      u_frame_chk.e_count,        e);
        check_one("prbs",   u_frame_chk.prbs_err_count, prbs);
        check_one("seq",    u_frame_chk.seq_err_count,  seq);
        check_one("blk",    blk_err_count,              blk);
    endtask

    task check_one(input string what, input int got, input int expected);
        if (got != expected) begin
            error_count++;
            $display("[%0t] PCS CHECKER ERROR: %s = %0d, se esperaba %0d",
                     $time, what, got, expected);
        end
    endtask

endmodule

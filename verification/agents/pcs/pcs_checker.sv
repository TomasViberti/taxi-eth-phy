// pcs_checker.sv
//
// Checker PCS 10GBASE-R con lock
//
// Descramblea cada bloque. El descrambler es
// auto-sincronizante.
// Ante el primer bloque que no es el esperado se deslockea
// No decide si el test pasa: cuenta. El test llama a clear() antes del
// estímulo y a check_counts() al final.

module pcs_checker (
    input logic        clk,
    input logic [63:0] tx_data,   // payload del bloque, scrambleado
    input logic [1:0]  tx_hdr     // sync header, sin scramblear
);

    // Sync header. Bit 0 = primer bit transmitido:
    // "01" dato, "10" control
    localparam logic [1:0] SYNC_DATA = 2'b10;
    localparam logic [1:0] SYNC_CONTROL = 2'b01;

    // Block types (figura 49-7)
    localparam logic [7:0] BLOCK_TYPE_CONTROL    = 8'h1E;
    localparam logic [7:0] BLOCK_TYPE_START_4 = 8'h33;
    localparam logic [7:0] BLOCK_TYPE_START_0 = 8'h78;

    // Terminate con el /T/ en la posición k: BLOCK_TYPE_TERMINATE[k]
    localparam logic [7:0] BLOCK_TYPE_TERMINATE [8] = '{8'h87, 8'h99, 8'hAA, 8'hB4,
                                           8'hCC, 8'hD2, 8'hE1, 8'hFF};

    // Códigos de control de 7 bits (tabla 49-1)
    localparam logic [6:0] CODE_IDLE  = 7'h00;
    localparam logic [6:0] CODE_ERROR = 7'h1E;

    // Preámbulo y SFD (cl. 46.2.2)
    localparam logic [7:0] PREAMBLE = 8'h55;
    localparam logic [7:0] SFD = 8'hD5;

    // Tipo de bloque, igual que R_BLOCK_TYPE de la cl. 49.2.13.2.3
    typedef enum {BLOCK_CONTROL, BLOCK_START, BLOCK_DATA, BLOCK_TERMINATE, BLOCK_ERROR} block_type_t;

    // Estados. INTER_FRAME = entre frames (RX_C), IN_FRAME = dentro del frame (RX_D)
    typedef enum {UNLOCKED, INTER_FRAME, IN_FRAME} state_t;

    state_t state = UNLOCKED;
    int     pre_count;          // bytes de preámbulo + SFD recibidos en este frame

    // Lo que vio el checker desde el último clear()
    int frame_count    = 0;     // frames completos sin errores (start ... terminate)
    int e_count        = 0;     // códigos /E/ recibidos (un bloque de error = 8)
    int prbs_err_count = 0;     // datos que no cumplen la PRBS31
    int seq_err_count  = 0;     // bloques fuera de la secuencia de la figura 49-17
    int blk_err_count  = 0;     // bloques inválidos (cl. 49.2.4.6)
    int unlock_count   = 0;     // veces que se deslockeó

    // Contadores que no dieron lo que esperaba el test. Lo lee Python
    int error_count = 0;

    // Descrambler
    prbs u_prbs ();

    // Checker PRBS31 auto-sincronizante del payload (cl. 49.2.12, figura 49-11)
    logic [30:0] prbs_reg;      // últimos 31 bits recibidos. prbs_reg[0] = el más nuevo
    int          prbs_fill;     // cuántos bits se cargaron desde prbs_reset

    // En cada flanco: descramblea el bloque, lo clasifica y avanza la FSM
    always @(posedge clk) begin : monitor
        logic [63:0] block;
        block_type_t block_type;
        int          lane;
        logic        invalid;
        string       why;

        u_prbs.descramble(tx_data, block);
        classify(tx_hdr, block, block_type, lane, invalid, why);
        check_block(block, block_type, lane, invalid, why);
    end

    // PRBS31 (igual que en xgmii_checker)

    // Empieza a sincronizar la PRBS de cero
    task prbs_reset();
        prbs_fill = 0;
    endtask

    // Chequea un bit de dato recibido. bit_err = 1 si no es el que sigue en la PRBS31
    task prbs_check_bit(input logic bit_in, output logic bit_err);
        if (prbs_fill < 31) begin
            // Todavía no hay 31 bits: no se puede predecir, sólo se carga
            bit_err = 0;
            prbs_fill++;
        end else begin
            // Polinomio 1 + x^28 + x^31 y salida invertida (cl. 49.2.8)
            bit_err = (bit_in != ~(prbs_reg[27] ^ prbs_reg[30]));
        end
        // Entra el bit recibido: por eso se auto-sincroniza
        prbs_reg = {prbs_reg[29:0], bit_in};
    endtask

    // Clasificación del bloque 

    // Un código de control de 7 bits. Válidos: /I/ y /E/. Cada error se
    // cuenta acá, esté o no lockeado el checker
    task check_code(input logic [6:0] code, output logic code_ok, output logic is_error);
        code_ok  = (code == CODE_IDLE || code == CODE_ERROR);
        is_error = (code == CODE_ERROR);
        if (is_error) e_count++;
    endtask

    // Clasifica el bloque descrambleado en control, start, data, terminate o error.
    // - lane: posición del /S/ (0 o 4) o del /T/ (0 a 7)
    // - invalid: 1 si el bloque es inválido según la cl. 49.2.4.6. Un bloque
    //   válido con /E/ también es BLOCK_ERROR, pero no es inválido
    task classify(input  logic [1:0]  hdr,
                  input  logic [63:0] block,
                  output block_type_t block_type,
                  output int          lane,
                  output logic        invalid,
                  output string       why);
        logic [7:0] type_field;
        logic       code_ok;
        logic       is_error;
        logic       has_error;
        int         pos;

        type_field = block[7:0];
        lane       = 0;
        invalid    = 0;
        has_error  = 0;
        why        = "";

        // Header 01: bloque de dato, D0..D7 (figura 49-7)
        if (hdr == SYNC_DATA) begin
            block_type = BLOCK_DATA;
            return;
        end

        // Header 00 o 11: inválido (cl. 49.2.4.6 a)
        if (hdr != SYNC_CONTROL) begin
            block_type = BLOCK_ERROR;
            invalid    = 1;
            why        = "sync header 00 u 11";
            return;
        end

        // Header 10: bloque de control, el block type dice el formato
        block_type = BLOCK_ERROR;

        // 0x1E: 8 códigos de control C0..C7.
        if (type_field == BLOCK_TYPE_CONTROL) begin
            for (int i = 0; i < 8; i++) begin
                check_code(block[8 + 7*i +: 7], code_ok, is_error);
                if (!code_ok) invalid = 1;
                if (is_error) has_error = 1;
            end
            if (invalid)        why = "código de control que no está en la tabla 49-1";
            else if (has_error) why = "bloque con /E/";
            else                block_type = BLOCK_CONTROL;

        // 0x78: /S/ en la posición 0 + D1..D7
        end else if (type_field == BLOCK_TYPE_START_0) begin
            block_type = BLOCK_START;
            lane       = 0;

        // 0x33: C0..C3 + 4 bits en 0 + /S/ en la posición 4 + D5..D7
        end else if (type_field == BLOCK_TYPE_START_4) begin
            for (int i = 0; i < 4; i++) begin
                check_code(block[8 + 7*i +: 7], code_ok, is_error);
                if (!code_ok) invalid = 1;
            end
            if (block[39:36] != 4'h0) invalid = 1;
            if (invalid) why = "bloque 0x33 mal formado (figura 49-7)";
            else begin
                block_type = BLOCK_START;
                lane       = 4;
            end

        // Terminate: D0..D(k-1) + /T/ en la posición k + (7-k) bits en 0 +
        // C(k+1)..C7
        end else begin
            lane = -1;
            for (int k = 0; k < 8; k++)
                if (type_field == BLOCK_TYPE_TERMINATE[k]) lane = k;

            // Ningún block type conocido: reservado (cl. 49.2.4.6 b)
            if (lane < 0) begin
                invalid = 1;
                why     = "block type reservado";
                return;
            end

            // Bits sin usar después de los datos: se mandan en 0 (figura 49-7)
            pos = 8 + 8*lane;
            for (int i = 0; i < 7 - lane; i++)
                if (block[pos + i] != 1'b0) invalid = 1;

            // Códigos de control después del /T/
            pos = pos + (7 - lane);
            for (int i = lane + 1; i < 8; i++) begin
                check_code(block[pos +: 7], code_ok, is_error);
                if (!code_ok) invalid = 1;
                pos = pos + 7;
            end

            if (invalid) why = "bloque de terminate mal formado (figura 49-7)";
            else         block_type = BLOCK_TERMINATE;
        end
    endtask

    // Un bloque: según el estado, qué se espera y a dónde se pasa
    task check_block(input logic [63:0] block, input block_type_t block_type,
                     input int lane, input logic invalid, input string why);
        logic ok;

        case (state)

            // No sabe dónde está: no verifica nada.
            UNLOCKED: begin
                if (block_type == BLOCK_CONTROL)
                    lock(INTER_FRAME);
                else if (block_type == BLOCK_START) begin
                    lock(IN_FRAME);
                    start_frame(block, lane);
                end
            end

            // Entre frames (RX_C): sólo control, o start que empieza el próximo frame
            INTER_FRAME: begin
                if (block_type == BLOCK_CONTROL) begin
                    // sigue entre frames
                end else if (block_type == BLOCK_START) begin
                    state = IN_FRAME;
                    start_frame(block, lane);
                end else
                    unlock(block_type, invalid, why, "se esperaba control o start");
            end

            // Dentro del frame: data, o terminate que termina el frame
            IN_FRAME: begin
                if (block_type == BLOCK_DATA) begin
                    check_payload(block, 0, 8, ok);
                end else if (block_type == BLOCK_TERMINATE) begin
                    // D0..D(k-1) están en los bytes 1..k del bloque
                    check_payload(block >> 8, 0, lane, ok);
                    if (ok) begin
                        frame_count++;
                        state = INTER_FRAME;    // después del terminate tiene que venir control o start
                    end
                end else
                    unlock(block_type, invalid, why, "se esperaba data o terminate");
            end

        endcase
    endtask

    // Bloque start: arranca el frame y verifica los bytes de dato que trae.
    // 0x78 trae D1..D7 (6 PREAMBLE + SFD). 0x33 trae D5..D7 (3 PREAMBLE): el resto del
    // preámbulo y el SFD llegan en el bloque siguiente
    task start_frame(input logic [63:0] block, input int lane);
        logic ok;
        pre_count = 0;
        if (lane == 0) check_payload(block, 1, 8, ok);   // bytes 1..7
        else           check_payload(block, 5, 8, ok);   // bytes 5..7
    endtask

    // Bytes de dato del frame (del byte first al last-1): primero 6 PREAMBLE y el SFD
    // (cl. 46.2.2), después el payload por la PRBS31 (bit 0 primero).
    // ok = 0 si hubo un error (y ya se deslockeó)
    task check_payload(input logic [63:0] block, input int first, input int last,
                       output logic ok);
        logic [7:0] octet;
        logic       bit_err;

        ok = 1;
        for (int i = first; i < last; i++) begin
            octet = block[8*i +: 8];

            if (pre_count < 6) begin
                // Preámbulo
                if (octet != PREAMBLE) begin
                    unlock(BLOCK_DATA, 0, "", $sformatf("byte %0d: se esperaba preámbulo (0x55), llegó %h", i, octet));
                    ok = 0;
                    return;
                end
                pre_count++;

            end else if (pre_count == 6) begin
                // SFD: lo que sigue es el payload
                if (octet != SFD) begin
                    unlock(BLOCK_DATA, 0, "", $sformatf("byte %0d: se esperaba SFD (0xD5), llegó %h", i, octet));
                    ok = 0;
                    return;
                end
                pre_count++;
                prbs_reset();

            end else begin
                // Payload
                for (int b = 0; b < 8; b++) begin
                    prbs_check_bit(octet[b], bit_err);
                    if (bit_err) begin
                        unlock(BLOCK_DATA, 0, "", $sformatf("byte %0d, bit %0d: no cumple la PRBS31", i, b), 1);
                        ok = 0;
                        return;
                    end
                end
            end
        end
    endtask

    // Pasa a un estado lockeado desde UNLOCKED
    task lock(input state_t next);
        $display("[%0t] PCS CHECKER: lock (%s)", $time, next.name());
        state = next;
    endtask

    // Primer error: cuenta de qué tipo fue y se deslockea.
    task unlock(input block_type_t block_type, input logic invalid, input string why,
                input string expected, input bit prbs_err = 0);
        if (prbs_err)                  prbs_err_count++;
        else if (invalid)              blk_err_count++;
        else if (block_type != BLOCK_ERROR)    seq_err_count++;
        unlock_count++;
        $display("[%0t] PCS CHECKER: unlock (%s): bloque %s%s, %s",
                 $time, state.name(), block_type.name(),
                 (why != "") ? {" (", why, ")"} : "", expected);
        state = UNLOCKED;
    endtask


    // Pone los contadores en 0. El test lo llama antes del estímulo
    task clear();
        frame_count    = 0;
        e_count        = 0;
        prbs_err_count = 0;
        seq_err_count  = 0;
        blk_err_count  = 0;
        unlock_count   = 0;
    endtask

    // Compara lo que vio el checker con lo que dice la norma que tiene que
    // salir. Cada contador que no coincide suma 1 a error_count
    task check_counts(input int frames, input int e, input int prbs, input int seq,
                      input int blk = 0);
        $display("[%0t] PCS CHECKER: frames=%0d e=%0d prbs=%0d seq=%0d blk=%0d unlocks=%0d",
                 $time, frame_count, e_count, prbs_err_count, seq_err_count,
                 blk_err_count, unlock_count);
        check_one("frames", frame_count,    frames);
        check_one("e",      e_count,        e);
        check_one("prbs",   prbs_err_count, prbs);
        check_one("seq",    seq_err_count,  seq);
        check_one("blk",    blk_err_count,  blk);
    endtask

    task check_one(input string what, input int got, input int expected);
        if (got != expected) begin
            error_count++;
            $display("[%0t] PCS CHECKER ERROR: %s = %0d, se esperaba %0d",
                     $time, what, got, expected);
        end
    endtask

endmodule

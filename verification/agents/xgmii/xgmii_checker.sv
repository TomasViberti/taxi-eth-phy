// xgmii_checker.sv
//
// Checker XGMII

module xgmii_checker #(
    parameter string NAME = "XGMII"   // nombre que sale en el log
) (
    input logic        clk,   
    input logic [63:0] rxd,   
    input logic [7:0]  rxc    
);

    // Caracteres de control (tabla 46-3)
    localparam logic [7:0] IDLE  = 8'h07;
    localparam logic [7:0] START = 8'hFB;
    localparam logic [7:0] TERMINATE  = 8'hFD;
    localparam logic [7:0] ERROR = 8'hFE;

    localparam logic [7:0] PREAMBLE = 8'h55;
    localparam logic [7:0] SFD = 8'hD5;

    typedef enum {UNLOCKED, INTER_FRAME, IN_PREAMBLE, IN_SFD, IN_DATA} state_t;

    state_t state = UNLOCKED;
    int     pre_count; 

    int frame_count    = 0;     // frames completos sin errores
    int e_count        = 0;     // bytes de error recibidos
    int prbs_err_count = 0;     // datos que no cumplen la PRBS31 de la norma
    int seq_err_count  = 0;     // bytes fuera de la secuencia de la figura 46-3
    int unlock_count   = 0;     // veces que se deslockeó

    // Contadores que no dieron lo que esperaba el test. Lo lee Python
    int error_count = 0;

    // Ultimos 31 bits recibidos
    logic [30:0] prbs_reg; 

    // Cuantos bits se cargaron desde que se hizo un reset
    int          prbs_fill;  

    // En cada flanco, los 8 bytes de la palabra en orden de lane
    always @(posedge clk) begin : monitor
        for (int lane = 0; lane < 8; lane++)
            check_byte(lane, rxc[lane], rxd[8*lane +: 8]);
    end

    // Empieza a sincronizar la PRBS de cero
    task prbs_reset();
        prbs_fill = 0;
    endtask

    // Chequea un bit de dato recibido. bit_err = 1 si no es el que sigue en la PRBS31
    task prbs_check_bit(input logic bit_in, output logic bit_err);

        // Todavía no hay 31 bits
        if (prbs_fill < 31) begin
            bit_err = 0;
            prbs_fill++;
        end 
        else begin
            // Mismo polinomio que generate_prbs de prbs.sv y salida invertida 
            bit_err = (bit_in != ~(prbs_reg[27] ^ prbs_reg[30]));
        end

        // Entra el bit recibido
        prbs_reg = {prbs_reg[29:0], bit_in};
    endtask

    // /S/ válido: control 0xFB en lane 0 o 4
    function automatic logic is_start(input int lane, input logic is_ctrl, input logic [7:0] octet);
        return is_ctrl && octet == START && (lane == 0 || lane == 4);
    endfunction

    // Un byte de la XGMII: según el estado, qué se espera y a dónde se pasa
    task check_byte(input int lane, input logic is_ctrl, input logic [7:0] octet);
        logic bit_err;

        // /E/ se reconoce siempre, lockeado o no: es un carácter de control
        if (is_ctrl && octet == ERROR) e_count++;

        case (state)

            UNLOCKED: begin
                if (is_ctrl && octet == IDLE)
                    lock(INTER_FRAME, lane);
                else if (is_start(lane, is_ctrl, octet)) begin
                    pre_count = 0;
                    lock(IN_PREAMBLE, lane);
                end
            end

            // Entre frames: sólo /I/, o /S/ que empieza el próximo frame
            INTER_FRAME: begin
                if (is_ctrl && octet == IDLE) begin
                    // sigue entre frames
                end else if (is_start(lane, is_ctrl, octet)) begin
                    pre_count = 0;
                    state = IN_PREAMBLE;
                end else
                    unlock(lane, is_ctrl, octet, "se esperaba idle o start");
            end

            // Después del /S/: 6 bytes de dato 0x55
            IN_PREAMBLE: begin
                if (!is_ctrl && octet == PREAMBLE) begin
                    pre_count++;
                    if (pre_count == 6) state = IN_SFD;
                end else
                    unlock(lane, is_ctrl, octet, "se esperaba preámbulo (0x55)");
            end

            // Después del preámbulo: 1 byte de dato 0xD5.
            IN_SFD: begin
                if (!is_ctrl && octet == SFD) begin
                    // Aplico reset de la PRBS para que empiece a sincronizar desde cero
                    prbs_reset();
                    state = IN_DATA;
                end else
                    unlock(lane, is_ctrl, octet, "se esperaba SFD (0xD5)");
            end

            // Datos hasta el /T/, que puede caer en cualquier
            // lane. Cada bit de dato pasa por el checker PRBS31,
            // bit 0 primero
            IN_DATA: begin
                if (!is_ctrl) begin
                    for (int i = 0; i < 8; i++) begin
                        prbs_check_bit(octet[i], bit_err);
                        if (bit_err) begin
                            unlock(lane, is_ctrl, octet, $sformatf("el bit %0d no cumple la PRBS31", i), 1);
                            break;
                        end
                    end
                end else if (octet == TERMINATE) begin
                    frame_count++;
                    state = INTER_FRAME;
                end else
                    unlock(lane, is_ctrl, octet, "se esperaba data o terminate");
            end

        endcase
    endtask

    // Pasa a un estado lockeado desde UNLOCKED
    task lock(input state_t next, input int lane);
        $display("[%0t] %s CHECKER: lock en lane %0d (%s)", $time, NAME, lane, next.name());
        state = next;
    endtask

    task unlock(input int lane, input logic is_ctrl, input logic [7:0] octet,
                input string why, input bit prbs_err = 0);
        if (prbs_err)
            prbs_err_count++;
        else if (!(is_ctrl && octet == ERROR))
            seq_err_count++;     // un /E/ ya se contó en e_count
        unlock_count++;
        $display("[%0t] %s CHECKER: unlock en lane %0d (%s): ctrl=%b octet=%h, %s",
                 $time, NAME, lane, state.name(), is_ctrl, octet, why);
        state = UNLOCKED;
    endtask

    // Pone los contadores en 0. Se llama en los tests antes de contar errores
    task clear();
        frame_count    = 0;
        e_count        = 0;
        prbs_err_count = 0;
        seq_err_count  = 0;
        unlock_count   = 0;
    endtask

    // Compara lo que recibe el checker con la norma. Cada contador que no coincide suma 1 a error_count
    task check_counts(input int frames, input int e, input int prbs, input int seq);
        $display("[%0t] %s CHECKER: frames=%0d e=%0d prbs=%0d seq=%0d unlocks=%0d",
                 $time, NAME, frame_count, e_count, prbs_err_count, seq_err_count, unlock_count);
        check_one("frames", frame_count,    frames);
        check_one("e",      e_count,        e);
        check_one("prbs",   prbs_err_count, prbs);
        check_one("seq",    seq_err_count,  seq);
    endtask

    task check_one(input string what, input int got, input int expected);
        if (got != expected) begin
            error_count++;
            $display("[%0t] %s CHECKER ERROR: %s = %0d, se esperaba %0d",
                     $time, NAME, what, got, expected);
        end
    endtask

endmodule

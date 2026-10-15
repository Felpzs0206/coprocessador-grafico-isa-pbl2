// ============================================================
// Decodificador de Instrucoes - PBL_SD
// Separa a identificacao da instrucao da execucao.
// A execucao continua sendo sequenciada pela FSM da control_unit_32.
// ============================================================

module instruction_decoder (
    input  wire [31:0] instruction,

    output reg  [3:0]  opcode,
    output reg         valid,

    // Sinais de acao da instrucao
    output reg         do_color,
    output reg         do_clear,
    output reg         do_xy,
    output reg         do_wh,
    output reg         do_rect,
    output reg         do_tri,
    output reg         do_t0,
    output reg         do_t1,
    output reg         do_t2,
    output reg         do_mirror,
    output reg         do_halt,
    output reg         do_set_sprite, // Flag da instrução SET_SPRITE
    output reg         do_set_scroll, // Flag: liga/desenha background (+ scroll opcional)
    output reg         do_mv_scroll,  // Flag: só scroll do background (X/Y)
    output reg         do_mv_sprite,  // Flag da instrução MV_SPRITE
    output reg         do_ers_sprite, // Flag da instrução ERS_SPRITE
    output reg         do_ers_back,   // EXT 0x1: apaga/desliga background (ERS_BACK)
    output reg         do_dfn_prty,   // EXT 0x2: define prioridade do compositor (DFN_PRTY)
    output reg         do_mv_prty,    // EXT 0x3: altera prioridade do compositor (MV_PRTY)
    output reg         do_alu_op,     // EXT 0x4: operacao da ULA (ALU_OP)
    output reg         do_ldi,        // EXT 0x5: carregar imediato no registrador (LDI)

    // Campos extraídos para ULA / Banco de Registradores
    output reg  [4:0]  reg_rd,
    output reg  [4:0]  reg_rs1,
    output reg  [4:0]  reg_rs2,
    output reg  [3:0]  alu_func,
    output reg  [31:0] alu_imm,

    // Campos extraídos genéricos
    output reg  [7:0]  color,
    output reg  [8:0]  x,
    output reg  [7:0]  y,
    output reg  [8:0]  w,
    output reg  [7:0]  h,
    
    // Campos extraídos para SET_SPRITE
    output reg  [4:0]  sprite_id,
    output reg  [8:0]  sprite_x,
    output reg  [7:0]  sprite_y,
    output reg  [1:0]  sprite_mirror,
    output reg  [3:0]  sprite_tile,

    // Campo extraído para DFN_PRTY / MV_PRTY
    output reg  [1:0]  prty
);

    localparam OP_COLOR      = 4'h1;
    localparam OP_CLEAR      = 4'h2;
    localparam OP_XY         = 4'h3;
    localparam OP_WH         = 4'h4;
    localparam OP_RECT       = 4'h5;
    localparam OP_TRI        = 4'h6;
    localparam OP_SET_SPRITE = 4'h7; // Substituindo OP_T0 para seguir a nova ISA
    localparam OP_T1         = 4'h8;
    localparam OP_T2         = 4'h9;
    localparam OP_MIRROR     = 4'hA;
    localparam OP_SET_SCROLL = 4'hB; // Liga/desenha background (enable + scroll)
    localparam OP_MV_SCROLL  = 4'hE; // Só scroll do background (X,Y)
    localparam OP_MV_SPRITE  = 4'hC; // Move sprite (ID + nova posição)
    localparam OP_ERS_SPRITE = 4'hD; // Apaga/desabilita sprite (ID)
    localparam OP_HALT       = 4'hF;

    // Opcode 0x0 = prefixo de EXTENSÃO (único livre). Sub-opcode em inst[27:24].
    // Não altera nenhuma instrução existente; palavra 0x00000000 continua inválida (NOP).
    localparam OP_EXT        = 4'h0;
    localparam EXT_ERS_BACK  = 4'h1; // 0x01000000
    localparam EXT_DFN_PRTY  = 4'h2; // 0x0200000P  (P = inst[1:0])
    localparam EXT_MV_PRTY   = 4'h3; // 0x0300000P  (P = inst[1:0])
    localparam EXT_ALU_OP    = 4'h4; // 0x04......  ALU_OP Rd, Rs1, Rs2, Func
    localparam EXT_LDI       = 4'h5; // 0x05......  LDI Rd, Imm

    always @(*) begin
        opcode = instruction[31:28];
        valid = 1'b0;

        do_color  = 1'b0;
        do_clear  = 1'b0;
        do_xy     = 1'b0;
        do_wh     = 1'b0;
        do_rect   = 1'b0;
        do_tri    = 1'b0;
        do_t0     = 1'b0;
        do_t1     = 1'b0;
        do_t2     = 1'b0;
        do_mirror = 1'b0;
        do_halt   = 1'b0;
        do_set_sprite = 1'b0;
        do_set_scroll = 1'b0;
        do_mv_scroll  = 1'b0;
        do_mv_sprite  = 1'b0;
        do_ers_sprite = 1'b0;
        do_ers_back   = 1'b0;
        do_dfn_prty   = 1'b0;
        do_mv_prty    = 1'b0;
        do_alu_op     = 1'b0;
        do_ldi        = 1'b0;

        color = instruction[7:0];
        x     = instruction[26:18];
        y     = instruction[17:10];
        w     = instruction[26:18];
        h     = instruction[17:10];
        
        // Campos de sprite (SET / MV / ERS compartilham o mesmo packing)
        sprite_id     = instruction[27:23];
        sprite_x      = instruction[22:14];
        sprite_y      = instruction[13:6];
        sprite_mirror = instruction[5:4];
        sprite_tile   = instruction[3:0];
        prty          = instruction[1:0];

        // Campos para ULA e Banco de Registradores
        reg_rd        = instruction[23:19];
        reg_rs1       = instruction[18:14];
        reg_rs2       = instruction[13:9];
        alu_func      = instruction[3:0];
        alu_imm       = {13'd0, instruction[18:0]};

        case (instruction[31:28])
            OP_COLOR:      begin valid = 1'b1; do_color      = 1'b1; end
            OP_CLEAR:      begin valid = 1'b1; do_clear      = 1'b1; end
            OP_XY:         begin valid = 1'b1; do_xy         = 1'b1; end
            OP_WH:         begin valid = 1'b1; do_wh         = 1'b1; end
            OP_RECT:       begin valid = 1'b1; do_rect       = 1'b1; end
            OP_TRI:        begin valid = 1'b1; do_tri        = 1'b1; end
            OP_SET_SPRITE: begin valid = 1'b1; do_set_sprite = 1'b1; end
            OP_T1:         begin valid = 1'b1; do_t1         = 1'b1; end
            OP_T2:         begin valid = 1'b1; do_t2         = 1'b1; end
            OP_MIRROR:     begin valid = 1'b1; do_mirror     = 1'b1; end
            OP_SET_SCROLL: begin valid = 1'b1; do_set_scroll = 1'b1; end
            OP_MV_SCROLL:  begin valid = 1'b1; do_mv_scroll  = 1'b1; end
            OP_MV_SPRITE:  begin valid = 1'b1; do_mv_sprite  = 1'b1; end
            OP_ERS_SPRITE: begin valid = 1'b1; do_ers_sprite = 1'b1; end
            OP_HALT:       begin valid = 1'b1; do_halt       = 1'b1; end
            OP_EXT: begin
                case (instruction[27:24])
                    EXT_ERS_BACK: begin valid = 1'b1; do_ers_back = 1'b1; end
                    EXT_DFN_PRTY: begin valid = 1'b1; do_dfn_prty = 1'b1; end
                    EXT_MV_PRTY:  begin valid = 1'b1; do_mv_prty  = 1'b1; end
                    EXT_ALU_OP:   begin valid = 1'b1; do_alu_op   = 1'b1; end
                    EXT_LDI:      begin valid = 1'b1; do_ldi      = 1'b1; end
                    default:      begin valid = 1'b0; end
                endcase
            end
            default: begin valid = 1'b0; end
        endcase
    end

endmodule

module control_unit_32 (
    input  wire        clk,
    input  wire        reset,
    input  wire        rast_done,
    input  wire [9:0]  SW,

    // Sinais do FIFO de instruções
    input  wire        fifo_empty,
    input  wire [31:0] fifo_data,
    output wire        fifo_read_en,

    output reg         rast_start,
    output reg         rast_enable_clear,
    output reg         rast_tipo,
    output reg  [7:0]  rast_cor_p,

    output reg  [8:0]  rx0,
    output reg  [8:0]  rx1,
    output reg  [8:0]  rx2,

    output reg  [7:0]  ry0,
    output reg  [7:0]  ry1,
    output reg  [7:0]  ry2,

    output reg         busy,
    output reg         scene_done,

    // Interface de escrita para o Sprite Engine
    output reg         sprite_wr_en,
    output reg         sprite_wr_xy_only, // 1 = só X/Y (MV_SPRITE)
    output reg  [4:0]  sprite_wr_id,
    output reg  [31:0] sprite_attr,

    // Interface do Background Engine (enable + scroll)
    output reg         bg_enable,       // liga o desenho do background
    output reg         bg_scroll_wr_en, // pulse: atualiza scroll
    output reg  [8:0]  bg_scroll_x,
    output reg  [7:0]  bg_scroll_y,

    // Prioridade global do compositor (DFN_PRTY / MV_PRTY)
    output reg  [1:0]  priority_ctrl,

    // Status do Program Counter para os displays/LEDs
    output wire [4:0]  current_pc
);

    // ============================================================
    // Estados da máquina de controle
    // ============================================================
    localparam S_FETCH  = 3'd0;
    localparam S_DECODE = 3'd1;
    localparam S_EXEC   = 3'd2;
    localparam S_WAIT   = 3'd3;
    localparam S_HALT   = 3'd4;

    // ============================================================
    // Registradores
    // ============================================================
    reg [2:0]  state;
    wire [31:0] instruction; // Sai do Instruction Register (IR)

    // Retângulo
    reg [8:0]  rect_x;
    reg [7:0]  rect_y;
    reg [8:0]  rect_w;
    reg [7:0]  rect_h;

    // Vértices do triângulo
    reg [8:0]  tx0;
    reg [8:0]  tx1;
    reg [8:0]  tx2;

    reg [7:0]  ty0;
    reg [7:0]  ty1;
    reg [7:0]  ty2;

    // Cor atual
    reg [7:0]  current_color;

    // ============================================================
    // Instruction Fetch Unit & Instruction Register
    // ============================================================
    wire        fetch_enable;
    wire [31:0] ifu_instruction;
    wire        ifu_valid;
    wire        load_ir;
    wire        ifu_valid_fifo;
    wire [31:0] fifo_instruction;
    wire [31:0] active_instruction;
    wire        active_valid;
    wire        active_mem_empty;
    wire [4:0]  active_pc;

    // Modo de busca ativa: o programa fica na ROM/RAM interna inicializada
    // por data/game_program.hex. O HPS não precisa enviar cada instrução.
    // Mantemos a FIFO conectada como referência para o modo passivo futuro.
    wire active_mode = 1'b0;
    wire run_program = 1'b1;
    wire [4:0] program_pc_addr;
    wire [31:0] program_pc_data;
    wire [31:0] mem_hps_rdata;

    // Em busca ativa, só solicita uma leitura enquanto ainda não há
    // instrução válida pendente. Isso evita avançar o PC duas vezes.
    assign fetch_enable = (state == S_FETCH) &&
                          (active_mode ? !ifu_valid : 1'b1);
    assign load_ir      = ifu_valid;

    instruction_fetch_unit fetch_unit (
        .fifo_empty(fifo_empty),
        .fifo_data(fifo_data),
        .fetch_enable(fetch_enable && !active_mode),
        .fifo_read_en(fifo_read_en),
        .instruction_out(fifo_instruction),
        .instruction_valid(ifu_valid_fifo)
    );

    instr_mem_32 program_memory (
        .clk(clk),
        .pc_addr(program_pc_addr),
        .pc_data(program_pc_data),
        .hps_addr(5'd0),
        .hps_we(1'b0),
        .hps_wdata(32'd0),
        .hps_rdata(mem_hps_rdata)
    );

    instruction_fetch_mem program_fetch (
        .clk(clk),
        .reset(reset),
        .fetch_enable(fetch_enable && active_mode),
        .run(run_program),
        .soft_reset_pc(1'b0),
        .pc_addr(program_pc_addr),
        .pc_data(program_pc_data),
        .instruction_out(active_instruction),
        .instruction_valid(active_valid),
        .mem_empty(active_mem_empty),
        .pc(active_pc)
    );

    assign current_pc = active_pc;

    assign ifu_instruction = active_mode ? active_instruction : fifo_instruction;
    assign ifu_valid = active_mode ? active_valid : ifu_valid_fifo;

    instruction_register ir (
        .clk(clk),
        .reset(reset),
        .load_ir(load_ir),
        .instruction_in(ifu_instruction),
        .ir(instruction)
    );

    // ============================================================
    // Decodificador de instrucoes
    // ============================================================
    wire [3:0] opcode;
    wire       decode_valid;

    wire       dec_color;
    wire       dec_clear;
    wire       dec_xy;
    wire       dec_wh;
    wire       dec_rect;
    wire       dec_tri;
    wire       dec_t0;
    wire       dec_t1;
    wire       dec_t2;
    wire       dec_mirror;
    wire       dec_halt;
    wire       dec_set_sprite;
    wire       dec_set_scroll;
    wire       dec_mv_scroll;
    wire       dec_mv_sprite;
    wire       dec_ers_sprite;
    wire       dec_ers_back;
    wire       dec_dfn_prty;
    wire       dec_mv_prty;
    wire [1:0] dec_prty;

    wire       dec_do_alu_op;
    wire       dec_do_ldi;
    wire [4:0] dec_reg_rd;
    wire [4:0] dec_reg_rs1;
    wire [4:0] dec_reg_rs2;
    wire [3:0] dec_alu_func;
    wire [31:0] dec_alu_imm;

    wire [7:0] dec_color_value;
    wire [8:0] dec_x;
    wire [7:0] dec_y;
    wire [8:0] dec_w;
    wire [7:0] dec_h;

    wire [4:0] dec_sprite_id;
    wire [8:0] dec_sprite_x;
    wire [7:0] dec_sprite_y;
    wire [1:0] dec_sprite_mirror;
    wire [3:0] dec_sprite_tile;

    instruction_decoder decoder (
        .instruction(instruction),
        .opcode(opcode),
        .valid(decode_valid),

        .do_color(dec_color),
        .do_clear(dec_clear),
        .do_xy(dec_xy),
        .do_wh(dec_wh),
        .do_rect(dec_rect),
        .do_tri(dec_tri),
        .do_t0(dec_t0),
        .do_t1(dec_t1),
        .do_t2(dec_t2),
        .do_mirror(dec_mirror),
        .do_halt(dec_halt),
        .do_set_sprite(dec_set_sprite),
        .do_set_scroll(dec_set_scroll),
        .do_mv_scroll(dec_mv_scroll),
        .do_mv_sprite(dec_mv_sprite),
        .do_ers_sprite(dec_ers_sprite),
        .do_ers_back(dec_ers_back),
        .do_dfn_prty(dec_dfn_prty),
        .do_mv_prty(dec_mv_prty),
        .do_alu_op(dec_do_alu_op),
        .do_ldi(dec_do_ldi),

        .reg_rd(dec_reg_rd),
        .reg_rs1(dec_reg_rs1),
        .reg_rs2(dec_reg_rs2),
        .alu_func(dec_alu_func),
        .alu_imm(dec_alu_imm),

        .color(dec_color_value),
        .x(dec_x),
        .y(dec_y),
        .w(dec_w),
        .h(dec_h),
        
        .sprite_id(dec_sprite_id),
        .sprite_x(dec_sprite_x),
        .sprite_y(dec_sprite_y),
        .sprite_mirror(dec_sprite_mirror),
        .sprite_tile(dec_sprite_tile),
        .prty(dec_prty)
    );

    // ============================================================
    // ALU e Register File (Integração Datapath)
    // ============================================================
    wire [31:0] reg_read_data1;
    wire [31:0] reg_read_data2;
    wire [31:0] reg_write_data;
    wire        reg_we;

    wire [3:0]  alu_ctrl;
    wire [31:0] alu_result;
    wire        alu_zero;

    assign alu_ctrl = dec_alu_func;
    assign reg_write_data = dec_do_ldi ? dec_alu_imm : alu_result;
    assign reg_we = (state == S_EXEC) && (dec_do_alu_op || dec_do_ldi);

    register_file reg_file (
        .clk(clk),
        .we(reg_we),
        .read_addr1(dec_reg_rs1),
        .read_addr2(dec_reg_rs2),
        .write_addr(dec_reg_rd),
        .write_data(reg_write_data),
        .read_data1(reg_read_data1),
        .read_data2(reg_read_data2)
    );

    alu_32 alu (
        .a(reg_read_data1),
        .b(reg_read_data2),
        .alu_control(alu_ctrl),
        .result(alu_result),
        .zero(alu_zero)
    );

    // ============================================================
    // Máquina de estados
    // ============================================================
    always @(posedge clk) begin
        if (reset) begin
            state <= S_FETCH;
            
            rect_x <= 9'd0;
            rect_y <= 8'd0;
            rect_w <= 9'd0;
            rect_h <= 8'd0;

            tx0 <= 9'd0;
            tx1 <= 9'd0;
            tx2 <= 9'd0;

            ty0 <= 8'd0;
            ty1 <= 8'd0;
            ty2 <= 8'd0;

            current_color <= 8'd0;

            rast_start <= 1'b0;
            rast_enable_clear <= 1'b0;
            rast_tipo <= 1'b1;
            rast_cor_p <= 8'd0;

            rx0 <= 9'd0;
            rx1 <= 9'd0;
            rx2 <= 9'd0;

            ry0 <= 8'd0;
            ry1 <= 8'd0;
            ry2 <= 8'd0;

            busy <= 1'b0;
            scene_done <= 1'b0;

            sprite_wr_en <= 1'b0;
            sprite_wr_xy_only <= 1'b0;
            sprite_wr_id <= 5'd0;
            sprite_attr <= 32'd0;

            bg_enable       <= 1'b0; // desligado até SET_SCROLL / DRW_BACK
            bg_scroll_wr_en <= 1'b0;
            bg_scroll_x     <= 9'd0;
            bg_scroll_y     <= 8'd0;

            priority_ctrl   <= 2'b00; // Sprite > Poly > BG
        end
        else begin
            rast_start      <= 1'b0;
            sprite_wr_en    <= 1'b0; // pulse de 1 ciclo
            sprite_wr_xy_only <= 1'b0;
            bg_scroll_wr_en <= 1'b0; // pulse de 1 ciclo

            case (state)
                S_FETCH: begin
                    if (active_mode ? active_valid : !fifo_empty) begin
                        busy <= 1'b1;
                        state <= S_DECODE;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                S_DECODE: begin
                    if (decode_valid)
                        state <= S_EXEC;
                    else
                        state <= S_FETCH;
                end

                S_EXEC: begin
                    if (dec_color) begin
                        current_color <= dec_color_value;
                        state <= S_FETCH;
                    end
                    else if (dec_xy) begin
                        rect_x <= dec_x;
                        rect_y <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_wh) begin
                        rect_w <= dec_w;
                        rect_h <= dec_h;
                        state <= S_FETCH;
                    end
                    else if (dec_t0) begin
                        tx0 <= dec_x;
                        ty0 <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_set_sprite) begin
                        sprite_wr_en <= 1'b1;
                        sprite_wr_xy_only <= 1'b0;
                        sprite_wr_id <= dec_sprite_id;
                        // [31]=Enable, [30:29]=Prio(10), [28]=MirH, [27]=MirV, [26]=Pal, [25:17]=X, [16]=Res, [15:8]=Tile, [7:0]=Y
                        sprite_attr <= {1'b1, 2'b10, dec_sprite_mirror[1], dec_sprite_mirror[0], 1'b0, dec_sprite_x, 1'b0, {4'b0000, dec_sprite_tile}, dec_sprite_y};
                        state <= S_FETCH;
                    end
                    else if (dec_mv_sprite) begin
                        // MV_SPRITE: só X/Y — enable/tile/mirror permanecem
                        sprite_wr_en <= 1'b1;
                        sprite_wr_xy_only <= 1'b1;
                        sprite_wr_id <= dec_sprite_id;
                        sprite_attr <= {1'b0, 2'b00, 1'b0, 1'b0, 1'b0, dec_sprite_x, 1'b0, 8'd0, dec_sprite_y};
                        state <= S_FETCH;
                    end
                    else if (dec_ers_sprite) begin
                        // Apaga sprite: enable=0 (atributos completos zerados)
                        sprite_wr_en <= 1'b1;
                        sprite_wr_xy_only <= 1'b0;
                        sprite_wr_id <= dec_sprite_id;
                        sprite_attr <= 32'd0;
                        state <= S_FETCH;
                    end
                    else if (dec_set_scroll) begin
                        // SET_SCROLL / DRW_BACK: liga o background (+ scroll inicial)
                        bg_enable       <= 1'b1;
                        bg_scroll_wr_en <= 1'b1;
                        bg_scroll_x     <= dec_x;
                        bg_scroll_y     <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_mv_scroll) begin
                        // MV_SCROLL: só desloca o background (não mexe no enable)
                        bg_scroll_wr_en <= 1'b1;
                        bg_scroll_x     <= dec_x;
                        bg_scroll_y     <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_ers_back) begin
                        // ERS_BACK: desliga o background
                        bg_enable <= 1'b0;
                        state <= S_FETCH;
                    end
                    else if (dec_dfn_prty || dec_mv_prty) begin
                        // DFN_PRTY / MV_PRTY: define a prioridade do compositor (0..3)
                        priority_ctrl <= dec_prty;
                        state <= S_FETCH;
                    end
                    else if (dec_t1) begin
                        tx1 <= dec_x;
                        ty1 <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_t2) begin
                        tx2 <= dec_x;
                        ty2 <= dec_y;
                        state <= S_FETCH;
                    end
                    else if (dec_clear) begin
                        rast_enable_clear <= 1'b1;
                        rast_tipo <= 1'b1;
                        rast_cor_p <= 8'd0;
                        rx0 <= 9'd0; ry0 <= 8'd0;
                        rx1 <= 9'd1; ry1 <= 8'd1;
                        rx2 <= 9'd0; ry2 <= 8'd0;
                        rast_start <= 1'b1;
                        state <= S_WAIT;
                    end
                    else if (dec_rect) begin
                        rast_enable_clear <= 1'b0;
                        rast_tipo <= 1'b1;
                        rast_cor_p <= current_color;
                        rx0 <= rect_x; ry0 <= rect_y;
                        rx1 <= rect_w; ry1 <= rect_h;
                        rx2 <= 9'd0;   ry2 <= 8'd0;
                        rast_start <= 1'b1;
                        state <= S_WAIT;
                    end
                    else if (dec_tri) begin
                        rast_enable_clear <= 1'b0;
                        rast_tipo <= 1'b0;
                        rast_cor_p <= current_color;
                        rx0 <= rect_x; ry0 <= rect_y;   // vertice 0 do TRI vem do XY (opcode 0x7 agora e SET_SPRITE)
                        rx1 <= tx1; ry1 <= ty1;
                        rx2 <= tx2; ry2 <= ty2;
                        rast_start <= 1'b1;
                        state <= S_WAIT;
                    end
                    else if (dec_mirror) begin
                        state <= S_FETCH;
                    end
                    else if (dec_do_alu_op || dec_do_ldi) begin
                        state <= S_FETCH;
                    end
                    else if (dec_halt) begin
                        busy <= 1'b0;
                        scene_done <= 1'b1;
                        state <= S_HALT;
                    end
                    else begin
                        state <= S_FETCH;
                    end
                end

                S_WAIT: begin
                    if (rast_done) begin
                        rast_enable_clear <= 1'b0;
                        state <= S_FETCH;
                    end
                end

                S_HALT: begin
                    busy <= 1'b0;
                    scene_done <= 1'b1;
                end

                default: begin
                    state <= S_FETCH;
                end
            endcase
        end
    end
endmodule

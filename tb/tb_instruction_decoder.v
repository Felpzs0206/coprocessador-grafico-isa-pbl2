`timescale 1ns / 1ps

module tb_instruction_decoder;

    reg  [31:0] instruction;

    wire [3:0]  opcode;
    wire        valid;

    wire        do_color, do_clear, do_xy, do_wh, do_rect, do_tri;
    wire        do_t0, do_t1, do_t2, do_mirror, do_halt;
    wire        do_set_sprite, do_set_scroll, do_mv_scroll, do_mv_sprite, do_ers_sprite;
    wire        do_ers_back, do_dfn_prty, do_mv_prty, do_alu_op, do_ldi;

    wire [4:0]  reg_rd, reg_rs1, reg_rs2;
    wire [3:0]  alu_func;
    wire [31:0] alu_imm;

    wire [7:0]  color;
    wire [8:0]  x;
    wire [7:0]  y;
    wire [8:0]  w;
    wire [7:0]  h;

    wire [4:0]  sprite_id;
    wire [8:0]  sprite_x;
    wire [7:0]  sprite_y;
    wire [1:0]  sprite_mirror;
    wire [3:0]  sprite_tile;
    wire [1:0]  prty;

    integer errors = 0;

    instruction_decoder uut (
        .instruction(instruction),
        .opcode(opcode),
        .valid(valid),
        .do_color(do_color),
        .do_clear(do_clear),
        .do_xy(do_xy),
        .do_wh(do_wh),
        .do_rect(do_rect),
        .do_tri(do_tri),
        .do_t0(do_t0),
        .do_t1(do_t1),
        .do_t2(do_t2),
        .do_mirror(do_mirror),
        .do_halt(do_halt),
        .do_set_sprite(do_set_sprite),
        .do_set_scroll(do_set_scroll),
        .do_mv_scroll(do_mv_scroll),
        .do_mv_sprite(do_mv_sprite),
        .do_ers_sprite(do_ers_sprite),
        .do_ers_back(do_ers_back),
        .do_dfn_prty(do_dfn_prty),
        .do_mv_prty(do_mv_prty),
        .do_alu_op(do_alu_op),
        .do_ldi(do_ldi),
        .reg_rd(reg_rd),
        .reg_rs1(reg_rs1),
        .reg_rs2(reg_rs2),
        .alu_func(alu_func),
        .alu_imm(alu_imm),
        .color(color),
        .x(x),
        .y(y),
        .w(w),
        .h(h),
        .sprite_id(sprite_id),
        .sprite_x(sprite_x),
        .sprite_y(sprite_y),
        .sprite_mirror(sprite_mirror),
        .sprite_tile(sprite_tile),
        .prty(prty)
    );

    initial begin
        $display("=== INICIANDO TESTBENCH: instruction_decoder ===");

        // Teste 1: COLOR 0xFC (amarelo) -> hex 100000FC
        instruction = 32'h1000_00FC;
        #10;
        if (!valid || !do_color || color !== 8'hFC) begin
            $display("[ERRO] COLOR: valid=%b, do_color=%b, cor=%h (esp: FC)", valid, do_color, color);
            errors = errors + 1;
        end else begin
            $display("[PASS] COLOR decodificado corretamente");
        end

        // Teste 2: CLEAR -> hex 20000000
        instruction = 32'h2000_0000;
        #10;
        if (!valid || !do_clear) begin
            $display("[ERRO] CLEAR: valid=%b, do_clear=%b", valid, do_clear);
            errors = errors + 1;
        end else begin
            $display("[PASS] CLEAR decodificado corretamente");
        end

        // Teste 3: XY 250, 20
        // inst[31:28]=3, inst[26:18]=250 (9'b011111010), inst[17:10]=20 (8'b00010100)
        instruction = {4'h3, 1'b0, 9'd250, 8'd20, 10'd0};
        #10;
        if (!valid || !do_xy || x !== 9'd250 || y !== 8'd20) begin
            $display("[ERRO] XY: valid=%b, do_xy=%b, x=%0d, y=%0d", valid, do_xy, x, y);
            errors = errors + 1;
        end else begin
            $display("[PASS] XY decodificado corretamente (x=250, y=20)");
        end

        // Teste 4: RECT -> hex 50000000
        instruction = 32'h5000_0000;
        #10;
        if (!valid || !do_rect) begin
            $display("[ERRO] RECT: valid=%b, do_rect=%b", valid, do_rect);
            errors = errors + 1;
        end else begin
            $display("[PASS] RECT decodificado corretamente");
        end

        // Teste 5: TRI -> hex 60000000
        instruction = 32'h6000_0000;
        #10;
        if (!valid || !do_tri) begin
            $display("[ERRO] TRI: valid=%b, do_tri=%b", valid, do_tri);
            errors = errors + 1;
        end else begin
            $display("[PASS] TRI decodificado corretamente");
        end

        // Teste 6: SET_SPRITE id=1, x=160, y=100, mirror=2'b01, tile=4
        instruction = {4'h7, 5'd1, 9'd160, 8'd100, 2'b01, 4'd4};
        #10;
        if (!valid || !do_set_sprite || sprite_id !== 5'd1 || sprite_x !== 9'd160 ||
            sprite_y !== 8'd100 || sprite_mirror !== 2'b01 || sprite_tile !== 4'd4) begin
            $display("[ERRO] SET_SPRITE: id=%0d, x=%0d, y=%0d, mir=%b, tile=%0d",
                     sprite_id, sprite_x, sprite_y, sprite_mirror, sprite_tile);
            errors = errors + 1;
        end else begin
            $display("[PASS] SET_SPRITE decodificado com todos os campos");
        end

        // Teste 7: EXT: LDI R5, 42
        // inst[31:28]=0, inst[27:24]=5 (EXT_LDI), inst[23:19]=5 (Rd), inst[18:0]=42 (Imm)
        instruction = {4'h0, 4'h5, 5'd5, 19'd42};
        #10;
        if (!valid || !do_ldi || reg_rd !== 5'd5 || alu_imm !== 32'd42) begin
            $display("[ERRO] LDI: valid=%b, do_ldi=%b, rd=%0d, imm=%0d", valid, do_ldi, reg_rd, alu_imm);
            errors = errors + 1;
        end else begin
            $display("[PASS] LDI decodificado (R5 <- 42)");
        end

        // Teste 8: EXT: ALU_OP R3, R1, R2, Func=ADD(0)
        // inst[31:28]=0, inst[27:24]=4 (EXT_ALU_OP), inst[23:19]=3 (Rd), inst[18:14]=1 (Rs1), inst[13:9]=2 (Rs2), inst[3:0]=0 (Func)
        instruction = {4'h0, 4'h4, 5'd3, 5'd1, 5'd2, 5'd0, 4'd0};
        #10;
        if (!valid || !do_alu_op || reg_rd !== 5'd3 || reg_rs1 !== 5'd1 || reg_rs2 !== 5'd2 || alu_func !== 4'd0) begin
            $display("[ERRO] ALU_OP: valid=%b, do_alu_op=%b, rd=%0d, rs1=%0d, rs2=%0d, func=%0d",
                     valid, do_alu_op, reg_rd, reg_rs1, reg_rs2, alu_func);
            errors = errors + 1;
        end else begin
            $display("[PASS] ALU_OP decodificado (R3 = R1 ADD R2)");
        end

        // Teste 9: HALT -> hex F0000000
        instruction = 32'hF000_0000;
        #10;
        if (!valid || !do_halt) begin
            $display("[ERRO] HALT: valid=%b, do_halt=%b", valid, do_halt);
            errors = errors + 1;
        end else begin
            $display("[PASS] HALT decodificado corretamente");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH instruction_decoder: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH instruction_decoder: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

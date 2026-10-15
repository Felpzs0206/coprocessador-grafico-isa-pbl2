`timescale 1ns / 1ps

module tb_alu_32;

    reg  [31:0] a;
    reg  [31:0] b;
    reg  [3:0]  alu_control;
    wire [31:0] result;
    wire        zero;

    integer errors = 0;

    alu_32 uut (
        .a(a),
        .b(b),
        .alu_control(alu_control),
        .result(result),
        .zero(zero)
    );

    task check_alu(
        input [31:0] expected_res,
        input        expected_zero,
        input [127:0] op_name
    );
        begin
            #5;
            if (result !== expected_res || zero !== expected_zero) begin
                $display("[ERRO] %s | a=%0d, b=%0d, ctrl=%b => res=%0d (esp: %0d), zero=%b (esp: %b)",
                         op_name, a, b, alu_control, result, expected_res, zero, expected_zero);
                errors = errors + 1;
            end else begin
                $display("[PASS] %s | res=%0h, zero=%b", op_name, result, zero);
            end
        end
    endtask

    initial begin
        $display("=== INICIANDO TESTBENCH: alu_32 ===");

        // Teste 1: SOMA (ADD) - 4'b0000
        a = 32'd25; b = 32'd17; alu_control = 4'b0000;
        check_alu(32'd42, 1'b0, "ADD (25 + 17)");

        // Teste 2: SUBTRAÇÃO gerando zero - 4'b0001
        a = 32'd50; b = 32'd50; alu_control = 4'b0001;
        check_alu(32'd0, 1'b1, "SUB gerando zero (50 - 50)");

        // Teste 3: SUBTRAÇÃO normal
        a = 32'd100; b = 32'd35; alu_control = 4'b0001;
        check_alu(32'd65, 1'b0, "SUB (100 - 35)");

        // Teste 4: AND lógico - 4'b0010
        a = 32'hF0F0AA55; b = 32'hFFFF00FF; alu_control = 4'b0010;
        check_alu(32'hF0F00055, 1'b0, "AND logico");

        // Teste 5: OR lógico - 4'b0011
        a = 32'hF0000000; b = 32'h0000000F; alu_control = 4'b0011;
        check_alu(32'hF000000F, 1'b0, "OR logico");

        // Teste 6: XOR lógico - 4'b0100
        a = 32'hAAAAAAAA; b = 32'h55555555; alu_control = 4'b0100;
        check_alu(32'hFFFFFFFF, 1'b0, "XOR logico");

        // Teste 7: Deslocamento à esquerda (SLL) - 4'b0101
        a = 32'd3; b = 32'd4; alu_control = 4'b0101; // 3 << 4 = 48
        check_alu(32'd48, 1'b0, "SLL (3 << 4)");

        // Teste 8: Deslocamento à direita (SRL) - 4'b0110
        a = 32'd64; b = 32'd3; alu_control = 4'b0110; // 64 >> 3 = 8
        check_alu(32'd8, 1'b0, "SRL (64 >> 3)");

        // Teste 9: Default / Inválido
        a = 32'd10; b = 32'd20; alu_control = 4'b1111;
        check_alu(32'd0, 1'b1, "DEFAULT (res = 0)");

        if (errors == 0)
            $display(">>> TESTBENCH alu_32: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH alu_32: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

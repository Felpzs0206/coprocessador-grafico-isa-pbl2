`timescale 1ns / 1ps

module tb_instruction_register;

    reg         clk;
    reg         reset;
    reg         load_ir;
    reg  [31:0] instruction_in;
    wire [31:0] ir;

    integer errors = 0;

    instruction_register uut (
        .clk(clk),
        .reset(reset),
        .load_ir(load_ir),
        .instruction_in(instruction_in),
        .ir(ir)
    );

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        load_ir = 0;
        instruction_in = 32'h0;

        $display("=== INICIANDO TESTBENCH: instruction_register ===");

        // Teste 1: Reset zera o IR
        #25;
        reset = 0;
        #5;
        if (ir !== 32'd0) begin
            $display("[ERRO] IR nao resetou para 0: ir=%h", ir);
            errors = errors + 1;
        end else begin
            $display("[PASS] Reset do IR com sucesso");
        end

        // Teste 2: Carga de nova instrução com load_ir = 1
        @(negedge clk);
        instruction_in = 32'h3190_A000; // XY 100, 40
        load_ir = 1;
        @(posedge clk);
        #5;
        if (ir !== 32'h3190_A000) begin
            $display("[ERRO] Carga do IR falhou: ir=%h, esperado=3190A000", ir);
            errors = errors + 1;
        end else begin
            $display("[PASS] Carga de instrucao no IR com sucesso");
        end

        // Teste 3: load_ir = 0 deve reter a instrução mesmo se a entrada mudar
        @(negedge clk);
        load_ir = 0;
        instruction_in = 32'hFFFF_FFFF;
        @(posedge clk);
        #5;
        if (ir !== 32'h3190_A000) begin
            $display("[ERRO] IR nao reteve o valor anterior com load_ir=0: ir=%h", ir);
            errors = errors + 1;
        end else begin
            $display("[PASS] Retencao de instrucao no IR com sucesso");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH instruction_register: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH instruction_register: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

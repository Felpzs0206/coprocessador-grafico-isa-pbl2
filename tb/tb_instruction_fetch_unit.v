`timescale 1ns / 1ps

module tb_instruction_fetch_unit;

    reg         fifo_empty;
    reg  [31:0] fifo_data;
    reg         fetch_enable;

    wire        fifo_read_en;
    wire [31:0] instruction_out;
    wire        instruction_valid;

    integer errors = 0;

    instruction_fetch_unit uut (
        .fifo_empty(fifo_empty),
        .fifo_data(fifo_data),
        .fetch_enable(fetch_enable),
        .fifo_read_en(fifo_read_en),
        .instruction_out(instruction_out),
        .instruction_valid(instruction_valid)
    );

    initial begin
        $display("=== INICIANDO TESTBENCH: instruction_fetch_unit ===");

        // Caso 1: Fetch desabilitado e FIFO com dados
        fifo_empty = 0;
        fifo_data = 32'h1000_00E0;
        fetch_enable = 0;
        #10;
        if (fifo_read_en !== 1'b0 || instruction_valid !== 1'b0) begin
            $display("[ERRO] Caso 1: fetch desabilitado nao deve ler FIFO nem validar!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Caso 1: fetch desabilitado mantem leitura inativa");
        end

        // Caso 2: Fetch habilitado porem FIFO vazia (aguardando HPS)
        fifo_empty = 1;
        fifo_data = 32'h0000_0000;
        fetch_enable = 1;
        #10;
        if (fifo_read_en !== 1'b0 || instruction_valid !== 1'b0) begin
            $display("[ERRO] Caso 2: FIFO vazia gerou read_en ou valid!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Caso 2: FIFO vazia bloqueia leitura e validade corretamente");
        end

        // Caso 3: Fetch habilitado e FIFO com instrucao valida (Handshake bem sucedido)
        fifo_empty = 0;
        fifo_data = 32'h5000_0000; // RECT
        fetch_enable = 1;
        #10;
        if (fifo_read_en !== 1'b1 || instruction_valid !== 1'b1 || instruction_out !== 32'h5000_0000) begin
            $display("[ERRO] Caso 3: Handshake de fetch falhou: rd_en=%b, valid=%b, instr=%h",
                     fifo_read_en, instruction_valid, instruction_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] Caso 3: Handshake correto: leitura acionada e instrucao valida repassada");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH instruction_fetch_unit: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH instruction_fetch_unit: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

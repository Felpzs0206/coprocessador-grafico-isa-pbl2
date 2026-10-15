`timescale 1ns / 1ps

module tb_gpu_cmd_fifo;

    reg         clk;
    reg         reset;
    reg         wr_en;
    reg  [31:0] wr_data;
    wire        full;
    reg         rd_en;
    wire [31:0] rd_data;
    wire        empty;

    integer errors = 0;
    integer i;

    gpu_cmd_fifo #(
        .DEPTH(8),
        .ADDR_W(3)
    ) uut (
        .clk(clk),
        .reset(reset),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty)
    );

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        wr_en = 0;
        wr_data = 0;
        rd_en = 0;

        $display("=== INICIANDO TESTBENCH: gpu_cmd_fifo ===");

        // Teste 1: Estado inicial após Reset
        #25;
        reset = 0;
        #5;
        if (!empty || full) begin
            $display("[ERRO] Apos reset: empty=%b (esp: 1), full=%b (esp: 0)", empty, full);
            errors = errors + 1;
        end else begin
            $display("[PASS] Reset da FIFO OK (empty=1, full=0)");
        end

        // Teste 2: Escrita de 8 elementos até encher a FIFO
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            wr_en = 1;
            wr_data = 32'h1000_0000 + i;
            @(posedge clk);
        end
        @(negedge clk);
        wr_en = 0;
        #5;
        if (!full || empty) begin
            $display("[ERRO] FIFO deveria estar cheia: full=%b (esp: 1), empty=%b (esp: 0)", full, empty);
            errors = errors + 1;
        end else begin
            $display("[PASS] FIFO cheia com 8 elementos (full=1, empty=0)");
        end

        // Teste 3: Tentativa de escrita com FIFO cheia (overflow protegido)
        @(negedge clk);
        wr_en = 1;
        wr_data = 32'hDEAD_BEEF;
        @(posedge clk);
        @(negedge clk);
        wr_en = 0;

        // Teste 4: Leitura e verificação de ordem FIFO (First-In, First-Out)
        for (i = 0; i < 8; i = i + 1) begin
            #5;
            if (rd_data !== (32'h1000_0000 + i)) begin
                $display("[ERRO] Dado incorreto no indice %0d: lido=%h, esperado=%h", i, rd_data, 32'h1000_0000 + i);
                errors = errors + 1;
            end
            @(negedge clk);
            rd_en = 1;
            @(posedge clk);
        end
        @(negedge clk);
        rd_en = 0;
        #5;
        if (!empty || full) begin
            $display("[ERRO] FIFO deveria estar vazia apos 8 leituras: empty=%b, full=%b", empty, full);
            errors = errors + 1;
        end else begin
            $display("[PASS] Leitura e drenagem completa da FIFO com ordem correta");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH gpu_cmd_fifo: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH gpu_cmd_fifo: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

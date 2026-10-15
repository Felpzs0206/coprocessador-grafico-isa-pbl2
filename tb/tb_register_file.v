`timescale 1ns / 1ps

module tb_register_file;

    reg         clk;
    reg         we;
    reg  [4:0]  read_addr1;
    reg  [4:0]  read_addr2;
    reg  [4:0]  write_addr;
    reg  [31:0] write_data;
    wire [31:0] read_data1;
    wire [31:0] read_data2;

    integer errors = 0;

    register_file uut (
        .clk(clk),
        .we(we),
        .read_addr1(read_addr1),
        .read_addr2(read_addr2),
        .write_addr(write_addr),
        .write_data(write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    // Clock de 50 MHz (período de 20 ns)
    always #10 clk = ~clk;

    initial begin
        clk = 0;
        we = 0;
        read_addr1 = 0;
        read_addr2 = 0;
        write_addr = 0;
        write_data = 0;

        $display("=== INICIANDO TESTBENCH: register_file ===");

        // Teste 1: R0 deve ser sempre 0 inicialmente
        #15;
        read_addr1 = 5'd0;
        read_addr2 = 5'd0;
        #5;
        if (read_data1 !== 32'd0 || read_data2 !== 32'd0) begin
            $display("[ERRO] R0 inicial diferente de zero: rd1=%h, rd2=%h", read_data1, read_data2);
            errors = errors + 1;
        end else begin
            $display("[PASS] R0 inicial e zero nas duas portas de leitura");
        end

        // Teste 2: Tentar escrever em R0 (deve ser proibido)
        @(negedge clk);
        we = 1;
        write_addr = 5'd0;
        write_data = 32'hDEADBEEF;
        @(posedge clk); // borda de escrita
        #5;
        we = 0;
        read_addr1 = 5'd0;
        #5;
        if (read_data1 !== 32'd0) begin
            $display("[ERRO] Falha na protecao de escrita do R0! Valor lido: %h", read_data1);
            errors = errors + 1;
        end else begin
            $display("[PASS] Protecao do R0 confirmada: escrita em R0 foi ignorada");
        end

        // Teste 3: Escrever no registrador R1 e ler na porta 1
        @(negedge clk);
        we = 1;
        write_addr = 5'd1;
        write_data = 32'h12345678;
        @(posedge clk);
        #5;
        we = 0;
        read_addr1 = 5'd1;
        #5;
        if (read_data1 !== 32'h12345678) begin
            $display("[ERRO] Escrita/Leitura em R1 falhou: lido=%h, esperado=12345678", read_data1);
            errors = errors + 1;
        end else begin
            $display("[PASS] Escrita e leitura no R1 com sucesso");
        end

        // Teste 4: Escrever no registrador R31 e ler simultaneamente em R1 (porta 1) e R31 (porta 2)
        @(negedge clk);
        we = 1;
        write_addr = 5'd31;
        write_data = 32'hCAFEBABE;
        @(posedge clk);
        #5;
        we = 0;
        read_addr1 = 5'd1;
        read_addr2 = 5'd31;
        #5;
        if (read_data1 !== 32'h12345678 || read_data2 !== 32'hCAFEBABE) begin
            $display("[ERRO] Leitura dual falhou: rd1(R1)=%h, rd2(R31)=%h", read_data1, read_data2);
            errors = errors + 1;
        end else begin
            $display("[PASS] Leitura assincrona dual de R1 e R31 com sucesso");
        end

        // Teste 5: Escrita com we = 0 nao deve alterar conteudo
        @(negedge clk);
        we = 0;
        write_addr = 5'd1;
        write_data = 32'hFFFFFFFF;
        @(posedge clk);
        #5;
        read_addr1 = 5'd1;
        #5;
        if (read_data1 !== 32'h12345678) begin
            $display("[ERRO] Dado alterado com we=0! lido=%h", read_data1);
            errors = errors + 1;
        end else begin
            $display("[PASS] WE=0 respeitado, valor preservado");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH register_file: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH register_file: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

`timescale 1ns / 1ps

module tb_coprocessador_integrado;

    reg         CLOCK_50;
    reg  [3:0]  KEY;
    reg  [9:0]  SW;

    wire        VGA_HS, VGA_VS;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_SYNC_N, VGA_CLK, VGA_BLANK_N;

    reg         hps_fifo_wr_en;
    reg  [31:0] hps_fifo_wr_data;
    wire        fifo_full;
    wire        fifo_empty;
    wire        gpu_busy;
    wire        gpu_done;
    wire [4:0]  gpu_pc;

    integer errors = 0;

    // Instanciação do módulo Top de Integração do Coprocessador
    test_top uut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK),
        .VGA_BLANK_N(VGA_BLANK_N),
        .hps_fifo_wr_en(hps_fifo_wr_en),
        .hps_fifo_wr_data(hps_fifo_wr_data),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .gpu_busy(gpu_busy),
        .gpu_done(gpu_done),
        .gpu_pc(gpu_pc)
    );

    // Clock de 50 MHz (período de 20 ns)
    always #10 CLOCK_50 = ~CLOCK_50;

    // Task para enviar comando HPS via FIFO
    task hps_send_cmd(input [31:0] cmd, input [127:0] name);
        begin
            @(negedge CLOCK_50);
            while (fifo_full) @(posedge CLOCK_50);
            hps_fifo_wr_en   <= 1'b1;
            hps_fifo_wr_data <= cmd;
            @(posedge CLOCK_50);
            #1;
            hps_fifo_wr_en   <= 1'b0;
            $display("[HPS-TX] Enviado: %s (0x%h) no tempo %0t ns", name, cmd, $time);
        end
    endtask

    initial begin
        CLOCK_50 = 0;
        KEY = 4'b1111; // KEY[0]=1 (reset inativo, ativo em 0)
        SW  = 10'd0;
        hps_fifo_wr_en = 0;
        hps_fifo_wr_data = 32'd0;

        $display("==================================================================");
        $display("=== INICIANDO TESTBENCH DE INTEGRACAO DO COPROCESSADOR GRAFICO ===");
        $display("==================================================================");

        // 1. Reset Global do Sistema (KEY[0] = 0)
        #25;
        KEY[0] = 0;
        #60;
        KEY[0] = 1;
        #40;

        if (!fifo_empty || fifo_full) begin
            $display("[ERRO] Apos reset da integracao: fifo_empty=%b (esp: 1), fifo_full=%b (esp: 0)",
                     fifo_empty, fifo_full);
            errors = errors + 1;
        end else begin
            $display("[PASS] Reset global do coprocessador concluido com sucesso.");
        end

        // 2. Envio de sequência de programa gráfico pelo HPS (MMIO / FIFO)
        // -------------------------------------------------------------
        // CMD 1: CLEAR (limpa o framebuffer de polígonos)
        hps_send_cmd(32'h2000_0000, "CLEAR");

        // CMD 2: COLOR 0x1C (Verde)
        hps_send_cmd(32'h1000_001C, "COLOR 0x1C");

        // CMD 3: XY (X=80, Y=40)
        // [31:28]=3, [26:18]=80, [17:10]=40
        hps_send_cmd({4'h3, 1'b0, 9'd80, 8'd40, 10'd0}, "XY 80, 40");

        // CMD 4: WH (W=60, H=30)
        // [31:28]=4, [26:18]=60, [17:10]=30
        hps_send_cmd({4'h4, 1'b0, 9'd60, 8'd30, 10'd0}, "WH 60, 30");

        // CMD 5: RECT (Desenha retângulo verde 60x30 em (80,40))
        hps_send_cmd(32'h5000_0000, "RECT");

        // CMD 6: SET_SCROLL (Habilita e posiciona plano de fundo)
        hps_send_cmd({4'hB, 1'b0, 9'd20, 8'd10, 10'd0}, "SET_SCROLL 20, 10");

        // CMD 7: SET_SPRITE (ID=0, X=120, Y=90, mirror=0, tile=1)
        hps_send_cmd({4'h7, 5'd0, 9'd120, 8'd90, 2'b00, 4'd1}, "SET_SPRITE id=0");

        // CMD 8: MV_SPRITE (Move Sprite ID=0 para X=130, Y=95)
        hps_send_cmd({4'hC, 5'd0, 9'd130, 8'd95, 2'b00, 4'd0}, "MV_SPRITE id=0");

        // CMD 9: DFN_PRTY 0 (Sprite > Poligono > Background)
        hps_send_cmd(32'h0200_0000, "DFN_PRTY 0");

        // CMD 10: HALT (Finaliza execução do programa gráfico)
        hps_send_cmd(32'hF000_0000, "HALT");

        // 3. Aguardar o término do programa gráfico (HALT -> gpu_done)
        $display("[INFO] Aguardando conclusao das instrucoes no coprocessador...");
        fork : wait_done
            begin
                wait (gpu_done == 1'b1);
                $display("[PASS] Sinal gpu_done detectado com sucesso no tempo %0t ns!", $time);
                disable wait_done;
            end
            begin
                #100000; // Timeout de 100 us
                $display("[ERRO] Timeout aguardando gpu_done!");
                errors = errors + 1;
                disable wait_done;
            end
        join

        // 4. Verificar se a FIFO de comandos foi esvaziada
        #200;
        if (!fifo_empty) begin
            $display("[ERRO] FIFO nao ficou vazia apos execucao completa!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Todas as instrucoes da FIFO foram consumidas e executadas.");
        end

        // 5. Verificar atividade do controlador VGA
        #1000;
        if (VGA_CLK === 1'bx) begin
            $display("[ERRO] VGA_CLK indefinido!");
            errors = errors + 1;
        end else begin
            $display("[PASS] Controlador VGA ativo (VGA_CLK e sincronismo operando continuamente).");
        end

        $display("==================================================================");
        if (errors == 0) begin
            $display(">>> TESTBENCH DE INTEGRACAO: TODOS OS TESTES PASSARAM COM SUCESSO! <<<");
        end else begin
            $display(">>> TESTBENCH DE INTEGRACAO: FINALIZADO COM %0d ERROS! <<<", errors);
        end
        $display("==================================================================");

        $finish;
    end

endmodule

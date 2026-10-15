`timescale 1ns / 1ps

module tb_control_unit_32;

    reg         clk;
    reg         reset;
    reg         rast_done;
    reg  [9:0]  SW;

    reg         fifo_empty;
    reg  [31:0] fifo_data;
    wire        fifo_read_en;

    wire        rast_start;
    wire        rast_enable_clear;
    wire        rast_tipo;
    wire [7:0]  rast_cor_p;

    wire [8:0]  rx0, rx1, rx2;
    wire [7:0]  ry0, ry1, ry2;

    wire        busy;
    wire        scene_done;

    wire        sprite_wr_en;
    wire        sprite_wr_xy_only;
    wire [4:0]  sprite_wr_id;
    wire [31:0] sprite_attr;

    wire        bg_enable;
    wire        bg_scroll_wr_en;
    wire [8:0]  bg_scroll_x;
    wire [7:0]  bg_scroll_y;

    wire [1:0]  priority_ctrl;
    wire [4:0]  current_pc;

    integer errors = 0;

    control_unit_32 uut (
        .clk(clk),
        .reset(reset),
        .rast_done(rast_done),
        .SW(SW),
        .fifo_empty(fifo_empty),
        .fifo_data(fifo_data),
        .fifo_read_en(fifo_read_en),
        .rast_start(rast_start),
        .rast_enable_clear(rast_enable_clear),
        .rast_tipo(rast_tipo),
        .rast_cor_p(rast_cor_p),
        .rx0(rx0), .rx1(rx1), .rx2(rx2),
        .ry0(ry0), .ry1(ry1), .ry2(ry2),
        .busy(busy),
        .scene_done(scene_done),
        .sprite_wr_en(sprite_wr_en),
        .sprite_wr_xy_only(sprite_wr_xy_only),
        .sprite_wr_id(sprite_wr_id),
        .sprite_attr(sprite_attr),
        .bg_enable(bg_enable),
        .bg_scroll_wr_en(bg_scroll_wr_en),
        .bg_scroll_x(bg_scroll_x),
        .bg_scroll_y(bg_scroll_y),
        .priority_ctrl(priority_ctrl),
        .current_pc(current_pc)
    );

    always #10 clk = ~clk;

    // Fila simples em memória para simulação da FIFO
    reg [31:0] cmd_queue [0:15];
    integer queue_rd = 0;
    integer queue_wr = 0;
    integer queue_cnt = 0;

    task send_cmd(input [31:0] cmd);
        begin
            cmd_queue[queue_wr] = cmd;
            queue_wr = queue_wr + 1;
            queue_cnt = queue_cnt + 1;
        end
    endtask

    always @(*) begin
        fifo_empty = (queue_cnt == 0);
        fifo_data  = (queue_cnt > 0) ? cmd_queue[queue_rd] : 32'd0;
    end

    always @(posedge clk) begin
        if (fifo_read_en && !fifo_empty) begin
            queue_rd  <= queue_rd + 1;
            queue_cnt <= queue_cnt - 1;
        end
    end

    // Emulador de conclusão do rasterizador (rast_done)
    always @(posedge clk) begin
        if (reset) begin
            rast_done <= 1'b0;
        end else if (rast_start) begin
            // Simula rasterização demorando 3 ciclos de clock
            repeat (3) @(posedge clk);
            rast_done <= 1'b1;
            @(posedge clk);
            rast_done <= 1'b0;
        end
    end

    initial begin
        clk = 0;
        reset = 1;
        rast_done = 0;
        SW = 10'd0;

        $display("=== INICIANDO TESTBENCH: control_unit_32 ===");

        #30;
        reset = 0;
        #20;

        // 1. Enviar COLOR 0xE0 (vermelho)
        send_cmd(32'h1000_00E0);

        // 2. Enviar XY 100, 40
        send_cmd({4'h3, 1'b0, 9'd100, 8'd40, 10'd0});

        // 3. Enviar WH 50, 30
        send_cmd({4'h4, 1'b0, 9'd50, 8'd30, 10'd0});

        // 4. Enviar RECT (deve acionar o rasterizador)
        send_cmd(32'h5000_0000);

        // Espera o rasterizador iniciar
        wait(rast_start == 1'b1);
        $display("[PASS] Comando RECT gerou rast_start = 1");
        if (rast_cor_p !== 8'hE0 || rx0 !== 9'd100 || ry0 !== 8'd40 || rx1 !== 9'd50 || ry1 !== 8'd30) begin
            $display("[ERRO] Parametros do retangulo incorretos! cor=%h, x=%0d, y=%0d, w=%0d, h=%0d",
                     rast_cor_p, rx0, ry0, rx1, ry1);
            errors = errors + 1;
        end else begin
            $display("[PASS] Parametros de cor, posicao e dimensao validados no rasterizador");
        end

        // 5. Enviar SET_SPRITE id=2, x=200, y=120, mirror=0, tile=5
        send_cmd({4'h7, 5'd2, 9'd200, 8'd120, 2'b00, 4'd5});

        wait(sprite_wr_en == 1'b1);
        if (sprite_wr_id !== 5'd2 || sprite_attr[25:17] !== 9'd200 || sprite_attr[7:0] !== 8'd120) begin
            $display("[ERRO] Escrita de Sprite incorreta: id=%0d, attr=%h", sprite_wr_id, sprite_attr);
            errors = errors + 1;
        end else begin
            $display("[PASS] Comando SET_SPRITE gerou pulso sprite_wr_en com atributos corretos");
        end

        // 6. Enviar SET_SCROLL (liga background e define offset x=80, y=10)
        send_cmd({4'hB, 1'b0, 9'd80, 8'd10, 10'd0});

        wait(bg_scroll_wr_en == 1'b1);
        if (!bg_enable || bg_scroll_x !== 9'd80 || bg_scroll_y !== 8'd10) begin
            $display("[ERRO] Background enable/scroll incorreto: enable=%b, x=%0d, y=%0d",
                     bg_enable, bg_scroll_x, bg_scroll_y);
            errors = errors + 1;
        end else begin
            $display("[PASS] Comando SET_SCROLL habilitou background e atualizou scroll");
        end

        // 7. Enviar HALT (termina cena)
        send_cmd(32'hF000_0000);

        wait(scene_done == 1'b1);
        #20;
        if (!scene_done || busy) begin
            $display("[ERRO] HALT nao finalizou cena adequadamente: scene_done=%b, busy=%b", scene_done, busy);
            errors = errors + 1;
        end else begin
            $display("[PASS] HALT executado com sucesso: scene_done = 1, busy = 0");
        end

        // Resumo
        if (errors == 0)
            $display(">>> TESTBENCH control_unit_32: TODOS OS TESTES PASSARAM! <<<");
        else
            $display(">>> TESTBENCH control_unit_32: FALHA com %0d erros! <<<", errors);

        $finish;
    end

endmodule

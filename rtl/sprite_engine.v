/*
 * SPRITE ENGINE - Motor de Sprites com Pipeline
 * ==============================================
 * Gerencia 32 sprites de 16x16 pixels
 * (compostos por 4 tiles de 8x8).
 *
 * Implementa:
 *  - Espelhamento horizontal (H)
 *  - Espelhamento vertical (V)
 *  - Prioridade
 *  - Transparencia entre sprites (top-2 candidatos)
 *
 * Arquitetura:
 *  - Estagio 1: calculo combinacional da cobertura e endereco
 *               dos 2 melhores sprites (maior prio; empate = maior ID)
 *  - Estagio 2: pipeline de 1 ciclo para casar com a ROM dual-port
 *  - Saida: se o 1o pixel for transparente (8'h00), usa o 2o
 *
 * Transparencia:
 *  - Cor 8'h00 = transparente
 *  - Pixel transparente do sprite de cima revela o sprite de baixo
 *    (se houver); senao cai no compositor (poly/BG).
 *
 * Espelhamento:
 *
 * Normal:
 *
 *   Tile 0 | Tile 1
 *   --------+-------
 *   Tile 2 | Tile 3
 *
 * Horizontal:
 *
 *   Tile 1 | Tile 0
 *   --------+-------
 *   Tile 3 | Tile 2
 *
 * Vertical:
 *
 *   Tile 2 | Tile 3
 *   --------+-------
 *   Tile 0 | Tile 1
 *
 * Horizontal + Vertical:
 *
 *   Tile 3 | Tile 2
 *   --------+-------
 *   Tile 1 | Tile 0
 */

module sprite_engine (
    input wire clk,
    input wire reset,

    // ============================================================
    // COORDENADAS DO PIXEL
    // ============================================================

    input wire [8:0] pixel_x,      // 0..319
    input wire [7:0] pixel_y,      // 0..239


    // ============================================================
    // INTERFACE DE ESCRITA DOS ATRIBUTOS
    //
    // sprite_attr:
    //
    // [31]    = enable
    // [30:29] = prioridade
    // [28]    = mirror horizontal
    // [27]    = mirror vertical
    // [26]    = palette
    // [25:17] = posicao X
    // [16]    = reservado
    // [15:8]  = tile base
    // [7:0]   = posicao Y
    // ============================================================

    input wire [31:0] sprite_attr,
    input wire        wr_sprite,
    input wire        wr_xy_only,  // 1 = MV_SPRITE: atualiza so X/Y
    input wire [4:0]  sprite_id,


    // ============================================================
    // ROM DOS TILES (dual-port: 2 candidatos por pixel)
    // ============================================================

    output reg  [10:0] tile_addr,    // candidato 1 (maior prioridade)
    output reg  [10:0] tile_addr_b,  // candidato 2 (proximo)
    input  wire [7:0]  tile_data,    // cor do candidato 1
    input  wire [7:0]  tile_data_b,  // cor do candidato 2


    // ============================================================
    // SAIDAS
    // ============================================================

    output reg [7:0] sprite_color,
    output reg       sprite_hit_out
);


    // ============================================================
    // DEFINICOES
    // ============================================================

    localparam SPRITE_COUNT  = 32;
    localparam SPRITE_WIDTH  = 16;
    localparam SPRITE_HEIGHT = 16;
    localparam COLOR_TRANSPARENT = 8'h00;


    // ============================================================
    // ATRIBUTOS DOS 32 SPRITES
    // ============================================================

    reg [8:0] sprite_x      [0:SPRITE_COUNT-1];
    reg [7:0] sprite_y      [0:SPRITE_COUNT-1];
    reg [7:0] sprite_tile   [0:SPRITE_COUNT-1];

    reg [1:0] sprite_prio   [0:SPRITE_COUNT-1];

    reg       sprite_enable [0:SPRITE_COUNT-1];

    reg       sprite_mirror_h [0:SPRITE_COUNT-1];
    reg       sprite_mirror_v [0:SPRITE_COUNT-1];


    // ============================================================
    // VARIAVEIS DO ESTAGIO 1 — top-2 candidatos
    // ============================================================

    reg        comb_hit;
    reg [4:0]  comb_hit_id;
    reg [1:0]  comb_hit_prio;
    reg [10:0] comb_tile_addr;

    reg        comb_hit2;
    reg [4:0]  comb_hit2_id;
    reg [1:0]  comb_hit2_prio;
    reg [10:0] comb_tile_addr2;


    // ============================================================
    // VARIAVEIS TEMPORARIAS
    // ============================================================

    reg [8:0] rel_x;
    reg [7:0] rel_y;

    // Coordenadas depois do espelhamento
    reg [8:0] mirror_x;
    reg [7:0] mirror_y;

    // Tile dentro do sprite 16x16
    reg [1:0] t_offset;

    // Pixel dentro do tile 8x8
    reg [2:0] t_pixel_x;
    reg [2:0] t_pixel_y;

    reg [10:0] this_tile_addr;

    integer i;


    // ============================================================
    // ESTAGIO 2 — REGISTRADORES DE PIPELINE
    // ============================================================

    reg hit_d1;
    reg hit2_d1;


    // ============================================================
    // ESCRITA DOS ATRIBUTOS DOS SPRITES
    // ============================================================

    always @(posedge clk) begin

        if (reset) begin : reset_sprites

            integer j;

            for (j = 0; j < SPRITE_COUNT; j = j + 1) begin

                sprite_enable[j]   <= 1'b0;

                sprite_x[j]        <= 9'b0;
                sprite_y[j]        <= 8'b0;

                sprite_tile[j]     <= 8'b0;

                sprite_prio[j]     <= 2'b0;

                sprite_mirror_h[j] <= 1'b0;
                sprite_mirror_v[j] <= 1'b0;

            end

        end

        else if (wr_sprite) begin
            if (wr_xy_only) begin
                // MV_SPRITE: preserva enable, tile, mirror, prioridade
                sprite_x[sprite_id] <= sprite_attr[25:17];
                sprite_y[sprite_id] <= sprite_attr[7:0];
            end else begin
                // SET_SPRITE / ERS_SPRITE: atributos completos
                sprite_enable[sprite_id]   <= sprite_attr[31];
                sprite_prio[sprite_id]     <= sprite_attr[30:29];
                sprite_mirror_h[sprite_id] <= sprite_attr[28];
                sprite_mirror_v[sprite_id] <= sprite_attr[27];
                sprite_x[sprite_id]        <= sprite_attr[25:17];
                sprite_tile[sprite_id]     <= sprite_attr[15:8];
                sprite_y[sprite_id]        <= sprite_attr[7:0];
            end
        end

    end


    // ============================================================
    // ESTAGIO 1
    //
    // Procura os 2 melhores sprites que cobrem o pixel atual.
    // Criterio: maior prioridade; em empate, maior ID.
    // ============================================================

    always @* begin

        comb_hit        = 1'b0;
        comb_hit_id     = 5'b0;
        comb_hit_prio   = 2'b0;
        comb_tile_addr  = 11'b0;

        comb_hit2       = 1'b0;
        comb_hit2_id    = 5'b0;
        comb_hit2_prio  = 2'b0;
        comb_tile_addr2 = 11'b0;

        // Valores padrao das variaveis temporarias
        rel_x     = 9'b0;
        rel_y     = 8'b0;

        mirror_x  = 9'b0;
        mirror_y  = 8'b0;

        t_offset  = 2'b0;

        t_pixel_x = 3'b0;
        t_pixel_y = 3'b0;

        this_tile_addr = 11'b0;


        // ========================================================
        // VARRE OS 32 SPRITES
        // ========================================================

        for (i = 0; i < SPRITE_COUNT; i = i + 1) begin

            if (sprite_enable[i]) begin

                // =================================================
                // VERIFICA SE O PIXEL ESTA DENTRO DO SPRITE
                // =================================================

                if ((pixel_x >= sprite_x[i]) &&
                    (pixel_x < sprite_x[i] + SPRITE_WIDTH) &&
                    (pixel_y >= sprite_y[i]) &&
                    (pixel_y < sprite_y[i] + SPRITE_HEIGHT)) begin


                    // =============================================
                    // COORDENADA RELATIVA NORMAL
                    // =============================================

                    rel_x = pixel_x - sprite_x[i];
                    rel_y = pixel_y - sprite_y[i];


                    // =============================================
                    // ESPELHAMENTO DO SPRITE INTEIRO 16x16
                    // =============================================

                    if (sprite_mirror_h[i])
                        mirror_x = 9'd15 - rel_x;
                    else
                        mirror_x = rel_x;


                    if (sprite_mirror_v[i])
                        mirror_y = 8'd15 - rel_y;
                    else
                        mirror_y = rel_y;


                    // =============================================
                    // SELECAO DO TILE (grade 2x2)
                    // =============================================

                    t_offset = {
                        mirror_y[3],
                        mirror_x[3]
                    };


                    // =============================================
                    // PIXEL DENTRO DO TILE 8x8
                    // =============================================

                    t_pixel_x = mirror_x[2:0];
                    t_pixel_y = mirror_y[2:0];


                    // =============================================
                    // ENDERECO DO PIXEL NA ROM
                    // =============================================

                    this_tile_addr = {
                        sprite_tile[i][4:0] + {3'b000, t_offset},
                        t_pixel_y,
                        t_pixel_x
                    };


                    // =============================================
                    // RESOLUCAO DE PRIORIDADE — top-2
                    //
                    // Maior prioridade vence.
                    // Em empate, maior ID vence.
                    // =============================================

                    if (!comb_hit ||
                        sprite_prio[i] > comb_hit_prio ||
                        ((sprite_prio[i] == comb_hit_prio) &&
                         (i[4:0] > comb_hit_id))) begin

                        // O antigo 1o vira 2o
                        comb_hit2       = comb_hit;
                        comb_hit2_id    = comb_hit_id;
                        comb_hit2_prio  = comb_hit_prio;
                        comb_tile_addr2 = comb_tile_addr;

                        // Novo 1o
                        comb_hit       = 1'b1;
                        comb_hit_id    = i[4:0];
                        comb_hit_prio  = sprite_prio[i];
                        comb_tile_addr = this_tile_addr;

                    end
                    else if (!comb_hit2 ||
                             sprite_prio[i] > comb_hit2_prio ||
                             ((sprite_prio[i] == comb_hit2_prio) &&
                              (i[4:0] > comb_hit2_id))) begin

                        // Entra como 2o
                        comb_hit2       = 1'b1;
                        comb_hit2_id    = i[4:0];
                        comb_hit2_prio  = sprite_prio[i];
                        comb_tile_addr2 = this_tile_addr;

                    end

                end

            end

        end

    end


    // ============================================================
    // ENDERECOS DA ROM (dual-port)
    // ============================================================

    always @* begin
        tile_addr   = comb_tile_addr;
        tile_addr_b = comb_tile_addr2;
    end


    // ============================================================
    // ESTAGIO 2 — PIPELINE
    //
    // A ROM possui 1 ciclo de latencia.
    // Atrasamos os hits para casar com tile_data / tile_data_b.
    // ============================================================

    always @(posedge clk) begin

        if (reset) begin

            hit_d1  <= 1'b0;
            hit2_d1 <= 1'b0;

        end

        else begin

            hit_d1  <= comb_hit;
            hit2_d1 <= comb_hit2;

        end

    end


    // ============================================================
    // SAIDA DO SPRITE
    //
    // Se o pixel do 1o candidato for transparente, usa o 2o.
    // sprite_hit_out fica 1 se houver cor opaca de algum dos dois.
    // ============================================================

    always @* begin

        if (hit_d1 && (tile_data != COLOR_TRANSPARENT)) begin
            sprite_color   = tile_data;
            sprite_hit_out = 1'b1;
        end
        else if (hit2_d1 && (tile_data_b != COLOR_TRANSPARENT)) begin
            sprite_color   = tile_data_b;
            sprite_hit_out = 1'b1;
        end
        else begin
            sprite_color   = COLOR_TRANSPARENT;
            sprite_hit_out = 1'b0;
        end

    end

endmodule
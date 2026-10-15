module compositor (
    input wire clk,
    input wire reset,

    // Controle de prioridade dinâmico
    // 0: Sprite > Polígono > BG
    // 1: Polígono > Sprite > BG
    // 2: Sprite > BG > Polígono
    // 3: Polígono > BG > Sprite
    input wire [1:0] priority_ctrl, 

    input wire [7:0] bg_color,
    input wire [7:0] poly_color, // Antigo fb_color (cor do polígono vinda do rasterizador)
    input wire [7:0] sprite_color,
    input wire sprite_hit,

    output reg [7:0] final_color
);

    localparam COLOR_TRANSPARENT = 8'h00;

    // ============================================================
    // COMPOSIÇÃO COM PRIORIDADE DINÂMICA
    // ============================================================
    reg [7:0] composed_idx;

    always @(*) begin
        // Valores default (se tudo for transparente, usa o BG)
        composed_idx = bg_color;

        case (priority_ctrl)
            2'b00: begin
                // Sprite > Polígono > BG
                if (sprite_hit && sprite_color != COLOR_TRANSPARENT)
                    composed_idx = sprite_color;
                else if (poly_color != COLOR_TRANSPARENT)
                    composed_idx = poly_color;
                else
                    composed_idx = bg_color;
            end
            
            2'b01: begin
                // Polígono > Sprite > BG
                if (poly_color != COLOR_TRANSPARENT)
                    composed_idx = poly_color;
                else if (sprite_hit && sprite_color != COLOR_TRANSPARENT)
                    composed_idx = sprite_color;
                else
                    composed_idx = bg_color;
            end

            2'b10: begin
                // Sprite > BG > Polígono (Polígono escondido atrás do BG)
                if (sprite_hit && sprite_color != COLOR_TRANSPARENT)
                    composed_idx = sprite_color;
                else
                    composed_idx = bg_color;
            end

            2'b11: begin
                // Polígono > BG > Sprite (Sprite escondido atrás do BG)
                if (poly_color != COLOR_TRANSPARENT)
                    composed_idx = poly_color;
                else
                    composed_idx = bg_color;
            end
        endcase
    end

    // ============================================================
    // PALETA
    // Adiciona 1 ciclo de latência.
    // ============================================================
    reg [7:0] palette_ram [0:255];

    initial begin
        $readmemh("data/palette.hex", palette_ram);
    end

    always @(posedge clk) begin
        if (reset)
            final_color <= 8'h00;
        else
            final_color <= palette_ram[composed_idx];
    end

endmodule
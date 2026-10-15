// ============================================================================
// Frame Control Unit - Gerencia o Duplo Framebuffer (Ping-Pong)
// ============================================================================

module frame_control_unit (
    input  wire        clk_write,      // Clock do domínio de escrita (ex: 50MHz)
    input  wire        clk_read,       // Clock do domínio de leitura (ex: 25MHz)
    input  wire        reset,
    
    // Controle
    input  wire        swap_buffers,   // Sinal (pulso) para trocar os buffers
    
    // Porta de Escrita (Vem do Compositor / Rasterizador)
    input  wire [16:0] write_addr,
    input  wire [7:0]  write_data,
    input  wire        write_enable,
    
    // Porta de Leitura (Vai para o VGA Driver)
    input  wire [16:0] read_addr,
    output wire [7:0]  read_data
);

    // Registrador que indica qual buffer está sendo exibido na tela (0 ou 1)
    reg fb_exibicao; 

    // Troca os buffers na borda de subida do swap_buffers
    always @(posedge clk_write or posedge reset) begin
        if (reset) begin
            fb_exibicao <= 1'b0;
        end else if (swap_buffers) begin
            fb_exibicao <= ~fb_exibicao;
        end
    end

    // ============================================================
    // Fios do Framebuffer 0
    // ============================================================
    wire [16:0] fb0_write_addr;
    wire [7:0]  fb0_write_data;
    wire        fb0_write_en;
    wire [16:0] fb0_read_addr;
    wire [7:0]  fb0_read_data;

    // ============================================================
    // Fios do Framebuffer 1
    // ============================================================
    wire [16:0] fb1_write_addr;
    wire [7:0]  fb1_write_data;
    wire        fb1_write_en;
    wire [16:0] fb1_read_addr;
    wire [7:0]  fb1_read_data;

    // ============================================================
    // MULTIPLEXAÇÃO DE ESCRITA
    // Se fb_exibicao == 0 (FB0 na tela), escrevemos no FB1.
    // Se fb_exibicao == 1 (FB1 na tela), escrevemos no FB0.
    // ============================================================
    assign fb0_write_addr = write_addr;
    assign fb0_write_data = write_data;
    assign fb0_write_en   = (fb_exibicao == 1'b1) ? write_enable : 1'b0;

    assign fb1_write_addr = write_addr;
    assign fb1_write_data = write_data;
    assign fb1_write_en   = (fb_exibicao == 1'b0) ? write_enable : 1'b0;

    // ============================================================
    // MULTIPLEXAÇÃO DE LEITURA
    // O VGA sempre lê do buffer que está em "exibição".
    // ============================================================
    assign fb0_read_addr = read_addr;
    assign fb1_read_addr = read_addr;
    assign read_data     = (fb_exibicao == 1'b0) ? fb0_read_data : fb1_read_data;

    // ============================================================
    // INSTÂNCIAS DOS FRAMEBUFFERS
    // ============================================================
    framebuffer fb0_inst (
        .clk_w       (clk_write),
        .write_addr  (fb0_write_addr),
        .write_data  (fb0_write_data),
        .write_enable(fb0_write_en),
        
        .clk_r       (clk_read),
        .read_addr   (fb0_read_addr),
        .read_data   (fb0_read_data)
    );

    framebuffer fb1_inst (
        .clk_w       (clk_write),
        .write_addr  (fb1_write_addr),
        .write_data  (fb1_write_data),
        .write_enable(fb1_write_en),
        
        .clk_r       (clk_read),
        .read_addr   (fb1_read_addr),
        .read_data   (fb1_read_data)
    );

endmodule

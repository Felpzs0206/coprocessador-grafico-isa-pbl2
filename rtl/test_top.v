// ============================================================
// test_top.v
// - Correção CDC sprite (50 MHz → 25 MHz)
// - FIFO real de comandos (gpu_cmd_fifo)
// - Debouncer nos switches de comando
// - Um switch por instrução (sem conflito com prioridade):
//     SW[9] SET_SPRITE   (desenhar sprite)
//     SW[8] MV_SPRITE    (mover sprite)
//     SW[7] ERS_SPRITE   (apagar sprite)
//     SW[6] SET_SCROLL   (desenhar/ligar background)
//     SW[5] MV_SCROLL    (só scroll do background)
//     SW[4] ERS_BACK     (apagar/desligar background)      [EXT 0x1]
//     SW[3] DRW_POL      (desenhar retângulo: XY + WH + RECT, usa a cor atual)
//     SW[2] ERS_POL      (limpar polígonos = CLEAR)
//     SW[1] DFN_PRTY     (prioridade: Polígono > Sprite > BG) [EXT 0x2]
//     SW[0] SET_CLR_POL  (cor do polígono = COLOR 0xE0)
// - priority_ctrl agora vem da instrução DFN_PRTY / MV_PRTY (reset = 2'b00: Sprite > Poly > BG)
// - Pronto para gpu_avalon_slave (HPS) escrever na mesma FIFO
// ============================================================
module test_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire        VGA_HS, VGA_VS,
    output wire [7:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_SYNC_N, VGA_CLK, VGA_BLANK_N,

    // ---- HPS: injeta instruções 32-bit no caminho Fetch → Decoder ----
    input  wire        hps_fifo_wr_en,
    input  wire [31:0] hps_fifo_wr_data,
    output wire        fifo_full,
    output wire        fifo_empty,
    output wire        gpu_busy,
    output wire        gpu_done,
    output wire [4:0]  gpu_pc
);

    reg clk_25mhz = 1'b0;
    always @(posedge CLOCK_50)
        clk_25mhz <= ~clk_25mhz;

    wire reset = ~KEY[0];

    // ============================================================
    // VGA
    // ============================================================
    wire [9:0] next_x_vga, next_y_vga;
    wire       vga_is_active;
    localparam LEFT_BLANK_LOGICAL = 2;

    wire [8:0] x_logico = next_x_vga[9:1];
    wire [7:0] y_logico = next_y_vga[9:1];

    reg [8:0] col_in_line;
    always @(posedge clk_25mhz) begin
        if (reset || !vga_is_active)
            col_in_line <= 9'd0;
        else if (next_x_vga[0] == 1'b1)
            col_in_line <= col_in_line + 1'b1;
    end
    wire left_blank = vga_is_active && (col_in_line < LEFT_BLANK_LOGICAL);

    // ============================================================
    // FIFO DE COMANDOS (busca ativa)
    // HPS e switches escrevem aqui → Fetch lê → Decoder
    // ============================================================
    // fifo_empty / fifo_full são ports de saída
    wire [31:0] fifo_rd_data;
    wire        fifo_read_en;       // da control_unit
    wire        fifo_wr_en;
    wire [31:0] fifo_wr_data;

    // ============================================================
// DEBOUNCERS + 1 SWITCH POR INSTRUÇÃO
//   SW[9] = desenhar sprite     (SET_SPRITE)
//   SW[8] = mover sprite        (MV_SPRITE)
//   SW[7] = apagar sprite       (ERS_SPRITE)
//   SW[6] = desenhar/ligar BG   (SET_SCROLL)
//   SW[5] = scroll do BG        (MV_SCROLL)
// ============================================================
    wire sw9_rise, sw8_rise, sw7_rise, sw6_rise, sw5_rise;
    wire sw4_rise, sw3_rise, sw2_rise, sw1_rise, sw0_rise;
    wire sw9_lvl,  sw8_lvl,  sw7_lvl,  sw6_lvl,  sw5_lvl;
    wire sw4_lvl,  sw3_lvl,  sw2_lvl,  sw1_lvl,  sw0_lvl;

    switch_debouncer u_db9 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[9]), .sw_level(sw9_lvl), .sw_rise(sw9_rise));
    switch_debouncer u_db8 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[8]), .sw_level(sw8_lvl), .sw_rise(sw8_rise));
    switch_debouncer u_db7 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[7]), .sw_level(sw7_lvl), .sw_rise(sw7_rise));
    switch_debouncer u_db6 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[6]), .sw_level(sw6_lvl), .sw_rise(sw6_rise));
    switch_debouncer u_db5 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[5]), .sw_level(sw5_lvl), .sw_rise(sw5_rise));
    switch_debouncer u_db4 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[4]), .sw_level(sw4_lvl), .sw_rise(sw4_rise));
    switch_debouncer u_db3 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[3]), .sw_level(sw3_lvl), .sw_rise(sw3_rise));
    switch_debouncer u_db2 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[2]), .sw_level(sw2_lvl), .sw_rise(sw2_rise));
    switch_debouncer u_db1 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[1]), .sw_level(sw1_lvl), .sw_rise(sw1_rise));
    switch_debouncer u_db0 (.clk(CLOCK_50), .reset(reset), .sw_in(SW[0]), .sw_level(sw0_lvl), .sw_rise(sw0_rise));

    reg        sw_wr;
    reg [31:0] sw_data;

    // Sequência do DRW_POL (SW[3]): XY -> WH -> RECT, uma palavra por ciclo de escrita
    reg [1:0]  pol_step;   // 0 = ocioso, 1..3 = palavra a enviar

    always @(posedge CLOCK_50) begin
        if (reset) begin
            sw_wr    <= 1'b0;
            sw_data  <= 32'd0;
            pol_step <= 2'd0;
        end else begin
            sw_wr <= 1'b0;
            // Prioridade se dois switches subirem no mesmo ciclo: 9 > 8 > ... > 0
            // (a sequência do DRW_POL, quando em andamento, tem preferência)
            if (pol_step != 2'd0) begin
                if (!fifo_full) begin
                    sw_wr <= 1'b1;
                    case (pol_step)
                        2'd1: begin
                            // WH W=80 H=40
                            // OPCODE=4, W=80 (0x050)<<18, H=40 (0x28)<<10
                            sw_data  <= 32'h4140A000;
                            pol_step <= 2'd2;
                        end
                        2'd2: begin
                            // RECT (usa XY/WH/cor atual)
                            sw_data  <= 32'h50000000;
                            pol_step <= 2'd0;
                        end
                        default: pol_step <= 2'd0;
                    endcase
                end
            end else if (sw9_rise && !fifo_full) begin
                // SET_SPRITE ID=1 X=150 Y=120 tile=0
                sw_data <= 32'h70A59E00;
                sw_wr   <= 1'b1;
            end else if (sw8_rise && !fifo_full) begin
                // MV_SPRITE ID=1 X=200 Y=80 tile=0
                sw_data <= 32'hC0B21400;
                sw_wr   <= 1'b1;
            end else if (sw7_rise && !fifo_full) begin
                // ERS_SPRITE ID=1
                sw_data <= 32'hD0800000;
                sw_wr   <= 1'b1;
            end else if (sw6_rise && !fifo_full) begin
                // SET_SCROLL X=40 Y=20 → liga/desenha background
                sw_data <= 32'hB0A05000;
                sw_wr   <= 1'b1;
            end else if (sw5_rise && !fifo_full) begin
                // MV_SCROLL X=80 Y=40 → só desloca o background
                sw_data <= 32'hE140A000;
                sw_wr   <= 1'b1;
            end else if (sw4_rise && !fifo_full) begin
                // ERS_BACK → desliga o background (EXT: opcode 0, sub-op 1)
                sw_data <= 32'h01000000;
                sw_wr   <= 1'b1;
            end else if (sw3_rise && !fifo_full) begin
                // DRW_POL X=50 Y=30 W=80 H=40 → envia XY agora; WH e RECT nos próximos ciclos
                // XY: OPCODE=3, X=50 (0x032)<<18, Y=30 (0x1E)<<10
                sw_data  <= 32'h30C87800;
                sw_wr    <= 1'b1;
                pol_step <= 2'd1;
            end else if (sw2_rise && !fifo_full) begin
                // ERS_POL → CLEAR (limpa o framebuffer de polígonos)
                sw_data <= 32'h20000000;
                sw_wr   <= 1'b1;
            end else if (sw1_rise && !fifo_full) begin
                // DFN_PRTY prioridade=1 (Polígono > Sprite > BG) (EXT: opcode 0, sub-op 2)
                sw_data <= 32'h02000001;
                sw_wr   <= 1'b1;
            end else if (sw0_rise && !fifo_full) begin
                // SET_CLR_POL cor=0xE0 (vermelho) → COLOR
                sw_data <= 32'h100000E0;
                sw_wr   <= 1'b1;
            end
        end
    end

    // --- Fonte HPS: Assembly 32-bit → FIFO → Fetch → Decoder ---
    // Prioridade: HPS > switches
    assign fifo_wr_en   = hps_fifo_wr_en | sw_wr;
    assign fifo_wr_data = hps_fifo_wr_en ? hps_fifo_wr_data : sw_data;

    gpu_cmd_fifo #(.DEPTH(16)) u_cmd_fifo (
        .clk     (CLOCK_50),
        .reset   (reset),
        .wr_en   (fifo_wr_en),
        .wr_data (fifo_wr_data),
        .full    (fifo_full),
        .rd_en   (fifo_read_en),
        .rd_data (fifo_rd_data),
        .empty   (fifo_empty)
    );

    // ============================================================
    // CONTROL UNIT // instancia
    // ============================================================
    wire rast_start, rast_enable_clear, rast_tipo, rast_done;
    wire [7:0] rast_cor_p;
    wire [8:0] rx0, rx1, rx2;
    wire [7:0] ry0, ry1, ry2;
    wire control_busy, scene_done;
    assign gpu_busy = control_busy;
    assign gpu_done = scene_done;

    wire        sprite_wr_en_50;
    wire        sprite_wr_xy_only_50;
    wire [4:0]  sprite_wr_id_50;
    wire [31:0] sprite_attr_50;

    wire        bg_enable_50;
    wire        bg_scroll_wr_en_50;
    wire [8:0]  bg_scroll_x_50;
    wire [7:0]  bg_scroll_y_50;
    wire [1:0]  priority_ctrl_50;

    control_unit_32 control (
        .clk               (CLOCK_50),
        .reset             (reset),
        .rast_done         (rast_done),
        .SW                (SW),
        .fifo_empty        (fifo_empty),
        .fifo_data         (fifo_rd_data),
        .fifo_read_en      (fifo_read_en),
        .rast_start        (rast_start),
        .rast_enable_clear (rast_enable_clear),
        .rast_tipo         (rast_tipo),
        .rast_cor_p        (rast_cor_p),
        .rx0(rx0), .rx1(rx1), .rx2(rx2),
        .ry0(ry0), .ry1(ry1), .ry2(ry2),
        .busy              (control_busy),
        .scene_done        (scene_done),
        .sprite_wr_en      (sprite_wr_en_50),
        .sprite_wr_xy_only (sprite_wr_xy_only_50),
        .sprite_wr_id      (sprite_wr_id_50),
        .sprite_attr       (sprite_attr_50),
        .bg_enable         (bg_enable_50),
        .bg_scroll_wr_en   (bg_scroll_wr_en_50),
        .bg_scroll_x       (bg_scroll_x_50),
        .bg_scroll_y       (bg_scroll_y_50),
        .priority_ctrl     (priority_ctrl_50),
        .current_pc        (gpu_pc)
    );

    // ============================================================
    // CDC sprite write 50 → 25 MHz
    // ============================================================
    reg        wr_pending_50;
    reg [4:0]  capt_id_50;
    reg [31:0] capt_attr_50;
    reg        capt_xy_only_50;
    reg        clear_pending_sync0, clear_pending_sync1;
    reg        sprite_wr_en_25;
    reg        sprite_wr_xy_only_25;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            wr_pending_50      <= 1'b0;
            capt_id_50         <= 5'd0;
            capt_attr_50       <= 32'd0;
            capt_xy_only_50    <= 1'b0;
            clear_pending_sync0 <= 1'b0;
            clear_pending_sync1 <= 1'b0;
        end else begin
            clear_pending_sync0 <= sprite_wr_en_25;
            clear_pending_sync1 <= clear_pending_sync0;
            if (sprite_wr_en_50) begin
                capt_id_50      <= sprite_wr_id_50;
                capt_attr_50    <= sprite_attr_50;
                capt_xy_only_50 <= sprite_wr_xy_only_50;
                wr_pending_50   <= 1'b1;
            end else if (clear_pending_sync1) begin
                wr_pending_50 <= 1'b0;
            end
        end
    end

    reg pending_s0, pending_s1, pending_s2;
    reg [4:0]  sprite_wr_id_25;
    reg [31:0] sprite_attr_25;

    always @(posedge clk_25mhz) begin
        if (reset) begin
            pending_s0 <= 0; pending_s1 <= 0; pending_s2 <= 0;
            sprite_wr_en_25 <= 0;
            sprite_wr_xy_only_25 <= 0;
            sprite_wr_id_25 <= 0;
            sprite_attr_25  <= 0;
        end else begin
            pending_s0 <= wr_pending_50;
            pending_s1 <= pending_s0;
            pending_s2 <= pending_s1;
            sprite_wr_en_25 <= pending_s1 & ~pending_s2;
            if (pending_s1 & ~pending_s2) begin
                sprite_wr_id_25      <= capt_id_50;
                sprite_attr_25       <= capt_attr_50;
                sprite_wr_xy_only_25 <= capt_xy_only_50;
            end else begin
                sprite_wr_xy_only_25 <= 1'b0;
            end
        end
    end

    // ============================================================
    // RASTERIZER // instancia
    // ============================================================
    wire [16:0] rast_write_addr;
    wire [7:0]  rast_write_data;
    wire        rast_write_enable;

    rasterizer raster_inst (
        .clk(CLOCK_50), .reset(reset),
        .start(rast_start), .enable_clear(rast_enable_clear),
        .tipo_forma(rast_tipo), .cor_preenchimento(rast_cor_p), .cor_fundo(8'h00),
        .x0(rx0), .y0(ry0), .x1(rx1), .y1(ry1), .x2(rx2), .y2(ry2),
        .write_addr(rast_write_addr), .write_data(rast_write_data),
        .write_enable(rast_write_enable), .done(rast_done)
    );

    // ============================================================
    // CDC background: enable (nível) + scroll (50 → 25 MHz)
    // ============================================================
    // enable é nível estável → 2 FF de sincronização bastam
    reg bg_enable_s0, bg_enable_25;
    always @(posedge clk_25mhz) begin
        if (reset) begin
            bg_enable_s0 <= 1'b0;
            bg_enable_25 <= 1'b0;
        end else begin
            bg_enable_s0 <= bg_enable_50;
            bg_enable_25 <= bg_enable_s0;
        end
    end

    // scroll: pulse + captura (mesmo padrão do sprite)
    reg        bg_wr_pending_50;
    reg [8:0]  capt_scroll_x_50;
    reg [7:0]  capt_scroll_y_50;
    reg        bg_clear_s0, bg_clear_s1;
    reg        bg_scroll_wr_en_25;
    reg [8:0]  bg_scroll_x_25;
    reg [7:0]  bg_scroll_y_25;
    reg        bg_pend_s0, bg_pend_s1, bg_pend_s2;

    always @(posedge CLOCK_50) begin
        if (reset) begin
            bg_wr_pending_50 <= 1'b0;
            capt_scroll_x_50 <= 9'd0;
            capt_scroll_y_50 <= 8'd0;
            bg_clear_s0      <= 1'b0;
            bg_clear_s1      <= 1'b0;
        end else begin
            bg_clear_s0 <= bg_scroll_wr_en_25;
            bg_clear_s1 <= bg_clear_s0;
            if (bg_scroll_wr_en_50) begin
                capt_scroll_x_50 <= bg_scroll_x_50;
                capt_scroll_y_50 <= bg_scroll_y_50;
                bg_wr_pending_50 <= 1'b1;
            end else if (bg_clear_s1) begin
                bg_wr_pending_50 <= 1'b0;
            end
        end
    end

    always @(posedge clk_25mhz) begin
        if (reset) begin
            bg_pend_s0 <= 0; bg_pend_s1 <= 0; bg_pend_s2 <= 0;
            bg_scroll_wr_en_25 <= 0;
            bg_scroll_x_25 <= 0;
            bg_scroll_y_25 <= 0;
        end else begin
            bg_pend_s0 <= bg_wr_pending_50;
            bg_pend_s1 <= bg_pend_s0;
            bg_pend_s2 <= bg_pend_s1;
            bg_scroll_wr_en_25 <= bg_pend_s1 & ~bg_pend_s2;
            if (bg_pend_s1 & ~bg_pend_s2) begin
                bg_scroll_x_25 <= capt_scroll_x_50;
                bg_scroll_y_25 <= capt_scroll_y_50;
            end
        end
    end

    // ============================================================
    // MOVIMENTAÇÃO // teste
    // SET_SCROLL via FIFO sobrescreve background_x/y
    // ============================================================
    reg [19:0] move_counter;
    reg [8:0]  player_x, background_x;
    reg [7:0]  background_y;

    always @(posedge clk_25mhz) begin
        if (reset) begin
            move_counter <= 0; player_x <= 9'd150;
            background_x <= 0; background_y <= 0;
        end else if (bg_scroll_wr_en_25) begin
            background_x <= bg_scroll_x_25;
            background_y <= bg_scroll_y_25;
        end else if (move_counter == 20'd749999) begin
            move_counter <= 0;
            if (!KEY[1] && KEY[2] && player_x > 0) player_x <= player_x - 1'b1;
            else if (!KEY[2] && KEY[1] && player_x < 9'd304) player_x <= player_x + 1'b1;
            if (!KEY[2] && KEY[1]) background_x <= (background_x == 9'd319) ? 9'd0 : background_x + 1'b1;
            else if (!KEY[1] && KEY[2]) background_x <= (background_x == 9'd0) ? 9'd319 : background_x - 1'b1;
            if (SW[2] && !SW[3]) background_y <= (background_y == 8'd239) ? 8'd0 : background_y + 1'b1;
            else if (!SW[2] && SW[3]) background_y <= (background_y == 8'd0) ? 8'd239 : background_y - 1'b1;
        end else move_counter <= move_counter + 1'b1;
    end

    // ============================================================
    // SPRITE + BG
    // ============================================================
    wire [10:0] spr_tile_addr, spr_tile_addr_b;
    wire [7:0]  spr_tile_data, spr_tile_data_b, spr_color, bg_color;
    wire        spr_hit;

    sprite_engine sprite_inst (
        .clk(clk_25mhz), .reset(reset),
        .pixel_x(x_logico), .pixel_y(y_logico),
        .sprite_attr(sprite_attr_25), .wr_sprite(sprite_wr_en_25),
        .wr_xy_only(sprite_wr_xy_only_25), .sprite_id(sprite_wr_id_25),
        .tile_addr(spr_tile_addr), .tile_addr_b(spr_tile_addr_b),
        .tile_data(spr_tile_data), .tile_data_b(spr_tile_data_b),
        .sprite_color(spr_color), .sprite_hit_out(spr_hit)
    );
    sprite_tile_rom spr_rom_inst (
        .clk(clk_25mhz),
        .addr(spr_tile_addr), .addr_b(spr_tile_addr_b),
        .data(spr_tile_data), .data_b(spr_tile_data_b)
    );

    background_engine bg_inst (
        .clk(clk_25mhz), .reset(reset),
        .enable(bg_enable_25),   // ligado pela instrução SET_SCROLL / DRW_BACK
        .auto_scroll(1'b0),
        .scroll_x_in(background_x), .scroll_y_in(background_y),
        .pixel_x(x_logico), .pixel_y(y_logico), .bg_color(bg_color)
    );

    // ============================================================
    // POLY FB + COMPOSITOR + FCU + VGA
    // ============================================================
    wire [16:0] comp_addr;
    wire [7:0]  poly_color, final_color, vga_display_color;
    coord_to_addr conv_comp (.x(x_logico), .y(y_logico), .addr(comp_addr));
    framebuffer poly_fb (
        .clk_w(CLOCK_50), .write_addr(rast_write_addr), .write_data(rast_write_data),
        .write_enable(rast_write_enable), .clk_r(clk_25mhz), .read_addr(comp_addr), .read_data(poly_color)
    );

    // CDC simples do priority_ctrl (50 → 25 MHz)
    reg [1:0] priority_ctrl_25;
    always @(posedge clk_25mhz) begin
        if (reset) priority_ctrl_25 <= 2'b00;
        else       priority_ctrl_25 <= priority_ctrl_50;
    end

    compositor comp_inst (
        // priority_ctrl vem da instrução DFN_PRTY / MV_PRTY (reset: Sprite > Polígono > BG)
        .clk(clk_25mhz), .reset(reset), .priority_ctrl(priority_ctrl_25),
        .bg_color(bg_color), .poly_color(poly_color),
        .sprite_color(spr_color), .sprite_hit(spr_hit), .final_color(final_color)
    );

    reg [16:0] comp_write_addr;
    reg        comp_write_en;
    always @(posedge clk_25mhz) begin
        comp_write_addr <= comp_addr;
        comp_write_en   <= vga_is_active;
    end

    wire vsync_wire;
    reg  last_vsync;
    always @(posedge clk_25mhz) last_vsync <= vsync_wire;
    wire swap_pulse = (vsync_wire == 1'b0 && last_vsync == 1'b1);

    frame_control_unit fcu_inst (
        .clk_write(clk_25mhz), .clk_read(clk_25mhz), .reset(reset),
        .swap_buffers(swap_pulse),
        .write_addr(comp_write_addr), .write_data(final_color), .write_enable(comp_write_en),
        .read_addr(comp_addr), .read_data(vga_display_color)
    );

    wire [7:0] color_to_vga = left_blank ? 8'h00 : vga_display_color;
    vga_driver vga_inst (
        .clock(clk_25mhz), .reset(reset), .color_in(color_to_vga),
        .next_x(next_x_vga), .next_y(next_y_vga), .is_active(vga_is_active),
        .hsync(VGA_HS), .vsync(vsync_wire),
        .red(VGA_R), .green(VGA_G), .blue(VGA_B),
        .sync(VGA_SYNC_N), .clk(VGA_CLK), .blank(VGA_BLANK_N)
    );
    assign VGA_VS = vsync_wire;

endmodule
 
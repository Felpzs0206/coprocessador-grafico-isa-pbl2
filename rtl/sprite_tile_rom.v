module sprite_tile_rom (
    input  wire        clk,
    input  wire [10:0] addr,       // porta A — candidato 1
    input  wire [10:0] addr_b,     // porta B — candidato 2
    output wire [7:0]  data,       // cor porta A
    output wire [7:0]  data_b      // cor porta B
);

    wire [7:0] q_a;
    wire [7:0] q_b;

    // =========================================================================
    // Porta A — candidato de maior prioridade
    // =========================================================================
    altsyncram rom_port_a (
        .address_a       (addr),
        .clock0          (clk),
        .q_a             (q_a),

        .data_a          (8'b0),
        .wren_a          (1'b0),
        .aclr0           (1'b0),
        .aclr1           (1'b0),
        .address_b       (1'b1),
        .addressstall_a  (1'b0),
        .addressstall_b  (1'b0),
        .byteena_a       (1'b1),
        .byteena_b       (1'b1),
        .clock1          (1'b1),
        .clocken0        (1'b1),
        .clocken1        (1'b1),
        .clocken2        (1'b1),
        .clocken3        (1'b1),
        .data_b          (1'b1),
        .eccstatus       (),
        .q_b             (),
        .rden_a          (1'b1),
        .rden_b          (1'b1),
        .wren_b          (1'b0)
    );

    defparam
        rom_port_a.clock_enable_input_a   = "BYPASS",
        rom_port_a.clock_enable_output_a  = "BYPASS",
        rom_port_a.init_file              = "data/sprite_tiles.mif",
        rom_port_a.intended_device_family = "Cyclone V",
        rom_port_a.lpm_type               = "altsyncram",
        rom_port_a.numwords_a             = 2048,
        rom_port_a.operation_mode         = "ROM",
        rom_port_a.outdata_aclr_a         = "NONE",
        rom_port_a.outdata_reg_a          = "CLOCK0",
        rom_port_a.power_up_uninitialized = "FALSE",
        rom_port_a.widthad_a              = 11,
        rom_port_a.width_a                = 8,
        rom_port_a.width_byteena_a        = 1;

    // =========================================================================
    // Porta B — segundo candidato (sprite atras / transparencia)
    // =========================================================================
    altsyncram rom_port_b (
        .address_a       (addr_b),
        .clock0          (clk),
        .q_a             (q_b),

        .data_a          (8'b0),
        .wren_a          (1'b0),
        .aclr0           (1'b0),
        .aclr1           (1'b0),
        .address_b       (1'b1),
        .addressstall_a  (1'b0),
        .addressstall_b  (1'b0),
        .byteena_a       (1'b1),
        .byteena_b       (1'b1),
        .clock1          (1'b1),
        .clocken0        (1'b1),
        .clocken1        (1'b1),
        .clocken2        (1'b1),
        .clocken3        (1'b1),
        .data_b          (1'b1),
        .eccstatus       (),
        .q_b             (),
        .rden_a          (1'b1),
        .rden_b          (1'b1),
        .wren_b          (1'b0)
    );

    defparam
        rom_port_b.clock_enable_input_a   = "BYPASS",
        rom_port_b.clock_enable_output_a  = "BYPASS",
        rom_port_b.init_file              = "data/sprite_tiles.mif",
        rom_port_b.intended_device_family = "Cyclone V",
        rom_port_b.lpm_type               = "altsyncram",
        rom_port_b.numwords_a             = 2048,
        rom_port_b.operation_mode         = "ROM",
        rom_port_b.outdata_aclr_a         = "NONE",
        rom_port_b.outdata_reg_a          = "CLOCK0",
        rom_port_b.power_up_uninitialized = "FALSE",
        rom_port_b.widthad_a              = 11,
        rom_port_b.width_a                = 8,
        rom_port_b.width_byteena_a        = 1;

    assign data   = q_a;
    assign data_b = q_b;

endmodule

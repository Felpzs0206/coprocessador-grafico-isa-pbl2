module register_file (
    input  wire        clk,
    input  wire        we,           // Write Enable (Permite escrita no registrador)
    input  wire [4:0]  read_addr1,   // Endereço do registrador a ser lido na porta 1
    input  wire [4:0]  read_addr2,   // Endereço do registrador a ser lido na porta 2
    input  wire [4:0]  write_addr,   // Endereço do registrador a ser escrito
    input  wire [31:0] write_data,   // Dado a ser escrito
    output wire [31:0] read_data1,   // Dado lido na porta 1
    output wire [31:0] read_data2    // Dado lido na porta 2
);

    // Declaração da memória: 32 registradores de 32 bits
    reg [31:0] registers [0:31];

    // Leitura combinacional: o dado fica disponível no mesmo ciclo de clock
    // Em muitas arquiteturas (como MIPS), o R0 é sempre 0 constante.
    assign read_data1 = (read_addr1 == 5'd0) ? 32'd0 : registers[read_addr1];
    assign read_data2 = (read_addr2 == 5'd0) ? 32'd0 : registers[read_addr2];

    // Escrita síncrona: o dado é gravado na borda de subida do relógio
    always @(posedge clk) begin
        // Não permitimos escrita no R0 se ele for considerado constante
        if (we && (write_addr != 5'd0)) begin
            registers[write_addr] <= write_data;
        end
    end

endmodule

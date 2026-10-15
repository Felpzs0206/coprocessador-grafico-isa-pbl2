module instruction_register (
    input  wire        clk,
    input  wire        reset,
    input  wire        load_ir,        // Sinal da Unidade de Controle para gravar o IR
    input  wire [31:0] instruction_in, // Instrução vinda da Unidade de Busca (FIFO)
    
    output reg  [31:0] ir              // Instrução travada (saída para o Decodificador)
);

    // O Registrador mantém a instrução estável até que o Controle peça a próxima
    always @(posedge clk) begin
        if (reset) begin
            ir <= 32'd0;
        end else if (load_ir) begin
            ir <= instruction_in;
        end
    end

endmodule

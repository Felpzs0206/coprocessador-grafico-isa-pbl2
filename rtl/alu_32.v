module alu_32 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_control,  // Sinais de controle da ULA vindos do decodificador
    output reg  [31:0] result,
    output wire        zero          // Flag indicando se o resultado é zero
);

    // CÓDIGOS DE CONTROLE DA ULA
    // 0000 : SOMA (ADD)
    // 0001 : SUBTRAÇÃO (SUB)
    // 0010 : E LÓGICO (AND)
    // 0011 : OU LÓGICO (OR)
    // 0100 : OU EXCLUSIVO (XOR)
    // 0101 : DESLOCAMENTO À ESQUERDA (SLL)
    // 0110 : DESLOCAMENTO À DIREITA (SRL)
    always @(*) begin
        case (alu_control)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a & b;
            4'b0011: result = a | b;
            4'b0100: result = a ^ b;
            4'b0101: result = a << b[4:0]; // Shift usa apenas os 5 bits baixos de 'b'
            4'b0110: result = a >> b[4:0];
            default: result = 32'd0;
        endcase
    end

    // Calcula a Flag Zero
    assign zero = (result == 32'd0);

endmodule

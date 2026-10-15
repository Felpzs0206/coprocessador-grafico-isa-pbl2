module instruction_fetch_unit (
    input  wire        fifo_empty,       // indica se a fila de comandos do HPS está vazia ['valid' da fila]
    input  wire [31:0] fifo_data,        // dado na ponta da fila ['data' da fila]
    input  wire        fetch_enable,     // se o controle pede uma nova instrução
    
    output wire        fifo_read_en,     // comando para avançar a fila (tipo um "POP") [vai no 'ready' da fila]
    output wire [31:0] instruction_out,  // instrução enviada para o registrador de instruções
    output wire        instruction_valid // sinaliza se a leitura foi bem sucedida
);

    // lê a fila se o controle pediu instrução e se a fila não estiver vazia
    assign fifo_read_en = fetch_enable & ~fifo_empty;
    
    // a instrução que vai para o registrador é o dado da fila
    assign instruction_out = fifo_data;
    
    // sinaliza para o controle/registrador de instruções se o dado que saiu é válido
    assign instruction_valid = fifo_read_en;

endmodule




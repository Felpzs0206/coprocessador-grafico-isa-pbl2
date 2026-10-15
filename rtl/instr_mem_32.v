// ============================================================
// instr_mem_32.v
// Memória de programa 32 palavras x 32 bits
// - Porta A: Fetch (leitura com PC)
// - Porta B: HPS (escrita/leitura via Avalon)
// Inicializa com data/game_program.hex ($readmemh)
// ============================================================
module instr_mem_32 (
    input  wire        clk,

    // Porta A — Fetch
    input  wire [4:0]  pc_addr,
    output reg  [31:0] pc_data,

    // Porta B — HPS
    input  wire [4:0]  hps_addr,
    input  wire        hps_we,
    input  wire [31:0] hps_wdata,
    output reg  [31:0] hps_rdata
);

    reg [31:0] mem [0:31];

    integer i;
    initial begin
        // Carrega o programa assembly montado (mesmo do projeto original)
        $readmemh("data/game_program.hex", mem);
        // Garante palavras restantes em 0 se o hex for menor
        // (o hex já tem 32 linhas)
    end

    // Porta A: leitura síncrona para o Fetch
    always @(posedge clk) begin
        pc_data <= mem[pc_addr];
    end

    // Porta B: leitura/escrita do HPS
    always @(posedge clk) begin
        if (hps_we)
            mem[hps_addr] <= hps_wdata;
        hps_rdata <= mem[hps_addr];
    end

endmodule

// ============================================================
// instruction_fetch_mem.v
// Fetch baseado em PC + memória de programa (caminho clássico)
//
// Fluxo:  PC → instr_mem → instruction → IR → decoder
//
// Alternativa ao fetch por FIFO. Usado quando o HPS carrega o
// programa (.hex / assembly 32 bits) na memória e dá start.
// ============================================================
module instruction_fetch_mem (
    input  wire        clk,
    input  wire        reset,

    input  wire        fetch_enable,   // control_unit pede próxima instrução
    input  wire        run,            // HPS armou o programa (1 = executar)
    input  wire        soft_reset_pc,  // HPS reinicia PC para 0

    // Interface com instr_mem_32 (porta A)
    output wire [4:0]  pc_addr,
    input  wire [31:0] pc_data,

    // Saída para o Instruction Register
    output wire [31:0] instruction_out,
    output wire        instruction_valid,
    output wire        mem_empty,      // 1 quando PC passou do fim / HALT tratado fora

    // Status
    output reg  [4:0]  pc
);

    // PC avança quando o controle pede fetch e o programa está em run
    assign pc_addr = pc;

    // Dado da memória (1 ciclo de latência da leitura síncrona)
    // Para simplificar: tratamos pc_data como válido no ciclo seguinte ao fetch_enable
    reg fetch_pending;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc            <= 5'd0;
            fetch_pending <= 1'b0;
        end else if (soft_reset_pc) begin
            pc            <= 5'd0;
            fetch_pending <= 1'b0;
        end else begin
            fetch_pending <= 1'b0;
            if (fetch_enable && run) begin
                fetch_pending <= 1'b1;
                pc <= pc + 5'd1;
            end
        end
    end

    // A memória é síncrona: no ciclo em que pedimos, pc_data ainda é do addr anterior.
    // Estratégia: output combinacional do addr atual (para BRAM síncrona real
    // o control_unit já espera 1 ciclo no S_DECODE). Aqui usamos pc_data direto.
    assign instruction_out  = pc_data;
    assign instruction_valid = fetch_pending && run;
    assign mem_empty = ~run;

endmodule

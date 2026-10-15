// ============================================================
// hps_instr_bridge.v
// Ponte Avalon-MM → caminho de instruções do coprocessador
//
// Fluxo:
//   Assembly 32 bits (software no HPS)
//        │  escreve em INSTR
//        ▼
//   FIFO de comandos (gpu_cmd_fifo)
//        │
//        ▼
//   instruction_fetch_unit   ← busca a palavra
//        │
//        ▼
//   instruction_register
//        │
//        ▼
//   instruction_decoder      ← vira opcode + campos
//        │
//        ▼
//   control_unit_32 (EXEC)
//
// Mapa (word address, base do lightweight bridge + offset do componente):
//   0  INSTR   (W)  empurra 1 instrução 32-bit na FIFO
//   1  STATUS  (R)  [0]empty [1]full [2]busy [3]done
//   2  CTRL    (W)  reservado
// ============================================================
module hps_instr_bridge (
    input  wire        clk,
    input  wire        reset_n,

    // Avalon-MM slave
    input  wire [3:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output wire        avs_waitrequest,

    // Status
    input  wire        gpu_busy,
    input  wire        gpu_done,
    input  wire        fifo_full,
    input  wire        fifo_empty,

    // FIFO → Fetch
    output reg         fifo_wr_en,
    output reg  [31:0] fifo_wr_data
);

    assign avs_waitrequest = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_wr_en   <= 1'b0;
            fifo_wr_data <= 32'd0;
            avs_readdata <= 32'd0;
        end else begin
            fifo_wr_en <= 1'b0; // pulso de 1 ciclo

            if (avs_write) begin
                case (avs_address[3:0])
                    4'h0: begin
                        // Uma palavra do assembly → FIFO → Fetch → Decoder
                        if (!fifo_full) begin
                            fifo_wr_data <= avs_writedata;
                            fifo_wr_en   <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            if (avs_read) begin
                case (avs_address[3:0])
                    4'h1: avs_readdata <= {28'd0, gpu_done, gpu_busy, fifo_full, fifo_empty};
                    default: avs_readdata <= 32'd0;
                endcase
            end
        end
    end

endmodule

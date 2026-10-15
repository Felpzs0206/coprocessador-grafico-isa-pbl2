// ============================================================
// gpu_avalon_slave.v
// Slave Avalon-MM para o Lightweight HPS-to-FPGA (0xFF20_0000+)
//
// Mapa de registradores (offset em bytes, word-addressed no avs):
//   0x00  INSTR   (W)  — escreve instrução ISA na FIFO de comandos
//   0x04  STATUS  (R)  — [0]=fifo_empty [1]=fifo_full [2]=gpu_busy [3]=gpu_done
//   0x08  CTRL    (W)  — [0]=soft_reset (opcional)
//
// Uso no HPS (Linux/baremetal):
//   volatile uint32_t *gpu = (uint32_t*)0xFF200000;
//   gpu[0] = 0x70A59E00;   // SET_SPRITE ...
//   while (gpu[1] & 0x4);  // espera busy
// ============================================================
module gpu_avalon_slave (
    input  wire        clk,
    input  wire        reset_n,

    // Avalon-MM slave (word address)
    input  wire [3:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output wire        avs_waitrequest,

    // Status da GPU
    input  wire        gpu_busy,
    input  wire        gpu_done,

    // Interface com a FIFO de comandos
    output reg         fifo_wr_en,
    output reg  [31:0] fifo_wr_data,
    input  wire        fifo_full,
    input  wire        fifo_empty
);

    assign avs_waitrequest = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_wr_en   <= 1'b0;
            fifo_wr_data <= 32'd0;
            avs_readdata <= 32'd0;
        end else begin
            fifo_wr_en <= 1'b0;  // pulso 1 ciclo

            if (avs_write) begin
                case (avs_address[3:0])
                    4'h0: begin  // INSTR
                        if (!fifo_full) begin
                            fifo_wr_data <= avs_writedata;
                            fifo_wr_en   <= 1'b1;
                        end
                    end
                    // 4'h2: CTRL — reservado
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

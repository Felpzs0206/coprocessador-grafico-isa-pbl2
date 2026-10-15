// ============================================================
// gpu_cmd_fifo.v — FIFO síncrona de comandos (32 bits)
// Compatível com Quartus (sem $clog2)
// ============================================================
module gpu_cmd_fifo #(
    parameter DEPTH  = 16,
    parameter ADDR_W = 4     // log2(DEPTH)
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        wr_en,
    input  wire [31:0] wr_data,
    output wire        full,

    input  wire        rd_en,
    output wire [31:0] rd_data,
    output wire        empty
);

    reg [31:0] mem [0:DEPTH-1];
    reg [ADDR_W:0] wr_ptr, rd_ptr;

    wire [ADDR_W:0] count = wr_ptr - rd_ptr;

    assign empty   = (count == 0);
    assign full    = (count == DEPTH);
    assign rd_data = mem[rd_ptr[ADDR_W-1:0]];

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule

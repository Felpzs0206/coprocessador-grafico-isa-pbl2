// ============================================================
// switch_debouncer.v
// Debounce de 1 bit + detector de borda de subida estável.
// Contador ~20 ms em clk de 50 MHz (1_000_000 ciclos).
// ============================================================
module switch_debouncer #(
    parameter integer STABLE_COUNTS = 1000000  // ~20 ms @ 50 MHz
) (
    input  wire clk,
    input  wire reset,
    input  wire sw_in,
    output reg  sw_level,   // nível estável debounced
    output reg  sw_rise     // pulse 1 ciclo na borda de subida estável
);

    localparam integer CNT_W = 20; // 2^20 > 1_000_000

    reg sw_sync0, sw_sync1;
    reg [CNT_W-1:0] cnt;
    reg sw_stable;

    always @(posedge clk) begin
        if (reset) begin
            sw_sync0  <= 1'b0;
            sw_sync1  <= 1'b0;
            cnt       <= {CNT_W{1'b0}};
            sw_stable <= 1'b0;
            sw_level  <= 1'b0;
            sw_rise   <= 1'b0;
        end else begin
            // 2 FF de sincronização (anti-metastabilidade)
            sw_sync0 <= sw_in;
            sw_sync1 <= sw_sync0;

            sw_rise <= 1'b0;

            if (sw_sync1 != sw_stable) begin
                if (cnt >= STABLE_COUNTS[CNT_W-1:0]) begin
                    sw_stable <= sw_sync1;
                    sw_level  <= sw_sync1;
                    cnt       <= {CNT_W{1'b0}};
                    if (sw_sync1 == 1'b1)
                        sw_rise <= 1'b1;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end else begin
                cnt <= {CNT_W{1'b0}};
            end
        end
    end

endmodule

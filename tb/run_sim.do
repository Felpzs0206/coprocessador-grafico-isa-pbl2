# ============================================================
# Script de Simulacao ModelSim / QuestaSim (PBL 02)
# ============================================================

# Cria a biblioteca work se nao existir
if {![file exists work]} {
    vlib work
}

puts "=== Compilando arquivos RTL ==="
vlog -work work rtl/alu_32.v
vlog -work work rtl/register_file.v
vlog -work work rtl/gpu_cmd_fifo.v
vlog -work work rtl/instruction_fetch_unit.v
vlog -work work rtl/instruction_fetch_mem.v
vlog -work work rtl/instruction_register.v
vlog -work work rtl/instruction_decoder.v
vlog -work work rtl/instr_mem_32.v
vlog -work work rtl/control_unit_32.v

# Modulos do subsistema grafico
vlog -work work rtl/vga_driver.v
vlog -work work rtl/sprite_engine.v
vlog -work work rtl/sprite_tile_rom.v
vlog -work work rtl/background_engine.v
vlog -work work rtl/background_rom_640x480.v
vlog -work work rtl/tilemap_ram.v
vlog -work work rtl/tile_patterns_rom.v
vlog -work work rtl/coord_to_addr.v
vlog -work work rtl/framebuffer.v
vlog -work work rtl/compositor.v
vlog -work work rtl/frame_control_unit.v
vlog -work work rtl/rasterizer.v
vlog -work work rtl/switch_debouncer.v
vlog -work work rtl/test_top.v

puts "=== Compilando Testbenches ==="
vlog -work work tb/tb_alu_32.v
vlog -work work tb/tb_register_file.v
vlog -work work tb/tb_gpu_cmd_fifo.v
vlog -work work tb/tb_instruction_fetch_unit.v
vlog -work work tb/tb_instruction_register.v
vlog -work work tb/tb_instruction_decoder.v
vlog -work work tb/tb_control_unit_32.v
vlog -work work tb/tb_coprocessador_integrado.v

puts ""
puts "=========================================================="
puts "Compilacao concluida com sucesso!"
puts "Para rodar qualquer teste individualmente na GUI, digite:"
puts "  vsim work.tb_alu_32"
puts "  vsim work.tb_register_file"
puts "  vsim work.tb_gpu_cmd_fifo"
puts "  vsim work.tb_instruction_fetch_unit"
puts "  vsim work.tb_instruction_register"
puts "  vsim work.tb_instruction_decoder"
puts "  vsim work.tb_control_unit_32"
puts "  vsim work.tb_coprocessador_integrado"
puts "=========================================================="

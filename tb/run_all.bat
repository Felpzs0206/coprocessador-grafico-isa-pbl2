@echo off
REM ============================================================
REM Script para compilar todos os testbenches do PBL 02
REM ============================================================

echo ============================================================
echo   Compilando RTL e Testbenches do Coprocessador Grafico
echo ============================================================

vlog -work work rtl/alu_32.v tb/tb_alu_32.v
if errorlevel 1 goto error

vlog -work work rtl/register_file.v tb/tb_register_file.v
if errorlevel 1 goto error

vlog -work work rtl/gpu_cmd_fifo.v tb/tb_gpu_cmd_fifo.v
if errorlevel 1 goto error

vlog -work work rtl/instruction_fetch_unit.v tb/tb_instruction_fetch_unit.v
if errorlevel 1 goto error

vlog -work work rtl/instruction_register.v tb/tb_instruction_register.v
if errorlevel 1 goto error

vlog -work work rtl/instruction_decoder.v tb/tb_instruction_decoder.v
if errorlevel 1 goto error

vlog -work work rtl/alu_32.v rtl/register_file.v rtl/instruction_decoder.v rtl/instruction_register.v rtl/instruction_fetch_unit.v rtl/instr_mem_32.v rtl/instruction_fetch_mem.v rtl/control_unit_32.v tb/tb_control_unit_32.v
if errorlevel 1 goto error

vlog -work work rtl/*.v tb/tb_coprocessador_integrado.v
if errorlevel 1 goto error

echo.
echo ============================================================
echo   TODOS OS TESTBENCHES FORAM COMPILADOS COM SUCESSO!
echo ============================================================
pause
exit /b 0

:error
echo.
echo [ERRO] Ocorreu uma falha durante a compilacao!
pause
exit /b 1

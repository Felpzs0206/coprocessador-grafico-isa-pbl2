/*
 * driver_arm_busca_ativa.S
 *
 * MODELO RESERVADO para a futura interface ARM/HPS do modo de BUSCA ATIVA.
 *
 * IMPORTANTE:
 * - O programa gráfico é lido pela FPGA de data/game_program.hex.
 * - Este arquivo NÃO envia instruções pela FIFO e NÃO é necessário para
 *   iniciar a busca ativa atual.
 * - Ainda não é um driver executável: falta implementar registradores de
 *   controle/status mapeados no Platform Designer e conectá-los ao RTL.
 * - Não inventar endereços: preencher os símbolos abaixo somente depois de
 *   definir o mapa de endereços real do sistema Qsys/Platform Designer.
 *
 * Interface futura sugerida:
 *   CTRL bit 0: start/run
 *   CTRL bit 1: reiniciar PC
 *   STATUS bit 0: busy
 *   STATUS bit 1: done/HALT
 *
 * Estes bits são apenas uma PROPOSTA, ainda não existem no hardware atual.
 * Por isso este arquivo fica como documentação/modelo e não deve ser
 * compilado nem executado até a interface de controle ser implementada.
 */

.syntax unified
.arch armv7-a
.arm

/* TODO (após criar os registradores Avalon no hardware):
 * 1. Definir CTRL_BASE e STATUS_OFFSET conforme o mapa real do sistema.
 * 2. Mapear os registradores pelo driver de kernel ou por uma aplicação
 *    Linux de teste autorizada.
 * 3. Escrever reset/start em CTRL.
 * 4. Ler STATUS até busy=0 ou done=1.
 * 5. Compilar com a toolchain ARM Linux correspondente ao HPS.
 */

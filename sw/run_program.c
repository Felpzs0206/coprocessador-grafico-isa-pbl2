/*
 * run_program.c
 *
 * Envia o programa assembly (32-bit) do coprocessador pelo HPS.
 *
 * Fluxo:
 *   game_program.hex (palavras 32-bit)
 *        |
 *        v  escreve em pio_cmd (offset 0)
 *   FIFO
 *        |
 *        v
 *   instruction_fetch_unit
 *        |
 *        v
 *   instruction_register
 *        |
 *        v
 *   instruction_decoder  --> opcode
 *        |
 *        v
 *   control_unit_32 (EXEC)
 *
 * Mapa (Lightweight bridge 0xFF200000):
 *   +0x00  pio_cmd     (W)  instrucao 32-bit
 *   +0x10  pio_status  (R)  [0]empty [1]full [2]busy [3]done
 *
 * Uso na placa:
 *   echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
 *   gcc -o run_program run_program.c
 *   ./run_program
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#define LW_BASE   0xFF200000u
#define LW_SPAN   0x1000u
#define CMD_OFF   0x00
#define STS_OFF   0x10

/* Programa montado a partir de data/game_program.asm / .hex */
static const uint32_t program[] = {
    0x20000000, /* CLEAR */
    0x100000FC, /* COLOR amarelo */
    0x33E85000, /* XY 250,20 */
    0x40787800, /* WH 30,30 */
    0x50000000, /* RECT */
    0x100000E0, /* COLOR vermelho */
    0x3190A000, /* XY 100,40 (vertice 0 do triangulo, lido pelo TRI) */
    0x82599000, /* T1 150,100 */
    0x90C99000, /* T2 50,100 */
    0x60000000, /* TRI */
    0x100000FF, /* COLOR branco */
    0x30C85000, /* XY 50,20 */
    0x40F03C00, /* WH 60,15 */
    0x50000000, /* RECT */
    0x1000001C, /* COLOR verde */
    0x31E16800, /* XY 120,90 */
    0x40A05000, /* WH 40,20 */
    0x50000000, /* RECT */
    0xB0000000, /* SET_SCROLL 0,0 (liga o background) */
    0x0508000A, /* LDI R1, 10 */
    0x04104200, /* ADD R2, R1, R1 (R2 = 20) */
    0xF0000000, /* HALT */
};
#define NPROG (sizeof(program)/sizeof(program[0]))

static void wait_not_full(volatile uint32_t *sts)
{
    int guard = 100000;
    while ((*sts & 0x2) && --guard) /* bit1 = full */
        ;
}

static void wait_idle(volatile uint32_t *sts)
{
    int guard = 1000000;
    while ((*sts & 0x4) && --guard) /* bit2 = busy */
        usleep(10);
}

int main(void)
{
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); return 1; }

    void *map = mmap(NULL, LW_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, LW_BASE);
    if (map == MAP_FAILED) { perror("mmap"); close(fd); return 1; }

    volatile uint32_t *cmd = (volatile uint32_t *)((char *)map + CMD_OFF);
    volatile uint32_t *sts = (volatile uint32_t *)((char *)map + STS_OFF);

    printf("=== HPS -> Fetch -> Decoder ===\n");
    printf("status inicial: empty=%u full=%u busy=%u done=%u\n",
           (*sts)&1, (*sts>>1)&1, (*sts>>2)&1, (*sts>>3)&1);

    for (unsigned i = 0; i < NPROG; i++) {
        wait_not_full(sts);
        printf("[%02u] envia 0x%08X\n", i, program[i]);
        *cmd = program[i];
        /* pequena pausa para o hardware detectar a mudanca do PIO */
        usleep(100);
    }

    wait_idle(sts);
    printf("status final: empty=%u full=%u busy=%u done=%u\n",
           (*sts)&1, (*sts>>1)&1, (*sts>>2)&1, (*sts>>3)&1);
    printf("Programa enviado. Instrucoes passaram pelo Fetch/Decoder.\n");

    munmap(map, LW_SPAN);
    close(fd);
    return 0;
}

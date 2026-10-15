/*
 * menu_gpu.c
 *
 * Menu de teste do coprocessador grafico (DE1-SoC) rodando no ARM/HPS (Linux).
 * Envia instrucoes de 32 bits pelo pio_Cmd (FIFO -> Fetch -> Decoder -> Control Unit).
 *
 * Mapa (Lightweight bridge 0xFF200000):
 *   +0x00  pio_Cmd     (W)  instrucao de 32 bits
 *   +0x10  pio_status  (R)  [0]empty [1]full [2]busy [3]done
 *
 * PRE-REQUISITOS (importante):
 *   1) rtl/control_unit_32.v precisa estar com  wire active_mode = 1'b0;
 *      (com 1'b1 a FPGA le o game_program.hex sozinha e IGNORA a FIFO do HPS).
 *      Recompile no Quartus e programe a placa com o .sof novo.
 *   2) Ponte habilitada no Linux:
 *        echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
 *   3) Rodar como root (usa /dev/mem).
 *
 * Compilar na placa:           gcc -O2 -Wall -o menu_gpu menu_gpu.c
 * Cross-compilar no PC:        arm-linux-gnueabihf-gcc -O2 -Wall -o menu_gpu menu_gpu.c
 * Teste no PC (sem hardware):  gcc -DSIM -Wall -Wextra -o menu_sim menu_gpu.c
 *
 * Uso:  ./menu_gpu                 -> menu interativo
 *       ./menu_gpu prog.asm        -> envia o arquivo (.asm ou .hex) e abre o menu
 *
 * Detalhes do hardware que este programa trata:
 *   - ghrd_top.v so enfileira quando o valor do pio_Cmd MUDA. Duas palavras iguais
 *     seguidas (ex.: RECT, RECT) perderiam a segunda. Por isso o programa insere
 *     uma palavra 0x00000000 (invalida, ignorada pelo decoder) entre elas.
 *   - HALT trava a control_unit ate o reset (KEY0). Por padrao o HALT e bloqueado.
 */

#define _DEFAULT_SOURCE
#include <ctype.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <unistd.h>

#define LW_BASE 0xFF200000u
#define LW_SPAN 0x1000u
#define CMD_OFF 0x00u
#define STS_OFF 0x10u

#define ST_EMPTY 0x1u
#define ST_FULL  0x2u
#define ST_BUSY  0x4u
#define ST_DONE  0x8u

/* Opcodes (instruction_decoder.v) */
#define OP_COLOR      0x1u
#define OP_CLEAR      0x2u
#define OP_XY         0x3u
#define OP_WH         0x4u
#define OP_RECT       0x5u
#define OP_TRI        0x6u
#define OP_SET_SPRITE 0x7u
#define OP_T1         0x8u
#define OP_T2         0x9u
#define OP_SET_SCROLL 0xBu
#define OP_MV_SPRITE  0xCu
#define OP_ERS_SPRITE 0xDu
#define OP_MV_SCROLL  0xEu
#define OP_HALT       0xFu
/* Opcode 0 = prefixo de extensao; sub-opcode em [27:24] */
#define EXT_ERS_BACK  0x1u
#define EXT_DFN_PRTY  0x2u
#define EXT_MV_PRTY   0x3u
#define EXT_ALU_OP    0x4u
#define EXT_LDI       0x5u

#define ARRAY_LEN(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* ------------------------------------------------------------------ */
/* Camada de hardware                                                  */
/* ------------------------------------------------------------------ */
#ifndef SIM
static int g_fd = -1;
static void *g_map = MAP_FAILED;
static volatile uint32_t *g_cmd;
static volatile uint32_t *g_sts;
#endif

static int hw_open(void)
{
#ifdef SIM
    printf("[SIM] sem hardware: as palavras so sao exibidas.\n");
    return 0;
#else
    g_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (g_fd < 0) {
        perror("open /dev/mem (rode como root)");
        return -1;
    }
    g_map = mmap(NULL, LW_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, g_fd, LW_BASE);
    if (g_map == MAP_FAILED) {
        perror("mmap");
        close(g_fd);
        g_fd = -1;
        return -1;
    }
    g_cmd = (volatile uint32_t *)((char *)g_map + CMD_OFF);
    g_sts = (volatile uint32_t *)((char *)g_map + STS_OFF);
    return 0;
#endif
}

static void hw_close(void)
{
#ifndef SIM
    if (g_map != MAP_FAILED) {
        munmap(g_map, LW_SPAN);
        g_map = MAP_FAILED;
    }
    if (g_fd >= 0) {
        close(g_fd);
        g_fd = -1;
    }
#endif
}

static uint32_t hw_status(void)
{
#ifdef SIM
    return ST_EMPTY;
#else
    return *g_sts;
#endif
}

static void hw_write(uint32_t w)
{
#ifdef SIM
    (void)w;
#else
    *g_cmd = w;
#endif
}

/* ------------------------------------------------------------------ */
/* Estado global                                                       */
/* ------------------------------------------------------------------ */
static volatile sig_atomic_t g_stop = 0;
static uint32_t g_last = 0;      /* ultimo valor escrito no pio_Cmd */
static unsigned long g_sent = 0; /* palavras enviadas (sem os separadores) */
static int g_allow_halt = 0;

static void on_sigint(int s)
{
    (void)s;
    g_stop = 1;
}

static void msleep(unsigned ms)
{
    if (ms)
        usleep(ms * 1000u);
}

/* ------------------------------------------------------------------ */
/* Envio de instrucoes                                                 */
/* ------------------------------------------------------------------ */
static int wait_not_full(void)
{
    int i;
    for (i = 0; i < 200000; i++) { /* ~2 s */
        if (!(hw_status() & ST_FULL))
            return 0;
        usleep(10);
    }
    return -1;
}

static int push_raw(uint32_t w)
{
    if (wait_not_full() < 0) {
        fprintf(stderr, "  ERRO: FIFO cheia. GPU parada (HALT?) ou nao consome a fila.\n"
                        "        Aperte KEY0 e confira active_mode=0.\n");
        return -1;
    }
    hw_write(w);
    g_last = w;
    usleep(20);
    return 0;
}

/* Envia uma palavra; txt (opcional) e o mnemonico para exibir. */
static int gpu_send_t(const char *txt, uint32_t w)
{
    if ((w >> 28) == OP_HALT && !g_allow_halt) {
        printf("  (HALT bloqueado: use a opcao 'h' do menu se realmente quiser)\n");
        return 0;
    }
    if (txt)
        printf("  %-38s 0x%08X\n", txt, w);
    else
        printf("  %-38s 0x%08X\n", "", w);

    if (w == 0 && g_last == 0)
        return 0; /* NOP sobre NOP: nada a fazer */

    if (w == g_last) { /* o hardware so enfileira quando o valor muda */
        if (push_raw(0x00000000u) < 0)
            return -1;
    }
    if (push_raw(w) < 0)
        return -1;
    g_sent++;
    return 0;
}

static int gpu_send(uint32_t w)
{
    return gpu_send_t(NULL, w);
}

/* 0 = ociosa, 1 = HALT (done=1), -1 = timeout */
static int gpu_wait_idle(unsigned timeout_ms)
{
    unsigned t, stable = 0;
    for (t = 0; t < timeout_ms; t++) {
        uint32_t s = hw_status();
        if (s & ST_DONE)
            return 1;
        if ((s & ST_EMPTY) && !(s & ST_BUSY)) {
            if (++stable >= 3)
                return 0;
        } else {
            stable = 0;
        }
        usleep(1000);
    }
    return -1;
}

static void print_status(void)
{
    uint32_t s = hw_status();
    printf("  status=0x%X  empty=%u full=%u busy=%u done=%u   (enviadas: %lu)\n",
           s & 0xF, s & 1, (s >> 1) & 1, (s >> 2) & 1, (s >> 3) & 1, g_sent);
    if (s & ST_DONE)
        puts("  [!] GPU em HALT: so volta com KEY0 (reset).");
}

static void finish(void)
{
    int r = gpu_wait_idle(3000);
    uint32_t s = hw_status();
    if (r == 0)
        puts("  [ok] GPU ociosa (fila vazia, busy=0).");
    else if (r == 1)
        puts("  [!] GPU em HALT (done=1). So volta com KEY0 (reset).");
    else if (!(s & ST_EMPTY) && !(s & ST_BUSY))
        puts("  [!] Ha dados na fila e a GPU esta parada: a FIFO nao esta sendo consumida.\n"
             "      Confira active_mode=0 em control_unit_32.v (e recompile/programe).");
    else
        puts("  [!] Timeout: GPU continua ocupada (busy=1). Veja LEDR0 e LEDR[6:2] (PC).");
}

/* ------------------------------------------------------------------ */
/* Codificacao das instrucoes                                          */
/* ------------------------------------------------------------------ */
static uint32_t enc_op(uint32_t op)
{
    return op << 28;
}

static uint32_t enc_xy(uint32_t op, uint32_t x, uint32_t y)
{
    return (op << 28) | ((x & 0x1FFu) << 18) | ((y & 0xFFu) << 10);
}

static uint32_t enc_sprite(uint32_t op, uint32_t id, uint32_t x, uint32_t y,
                           uint32_t mirror, uint32_t tile)
{
    return (op << 28) | ((id & 0x1Fu) << 23) | ((x & 0x1FFu) << 14) |
           ((y & 0xFFu) << 6) | ((mirror & 3u) << 4) | (tile & 0xFu);
}

static uint32_t enc_ext(uint32_t sub)
{
    return sub << 24;
}

static uint32_t enc_color(uint32_t c)
{
    return enc_op(OP_COLOR) | (c & 0xFFu);
}

static uint32_t enc_ldi(uint32_t rd, uint32_t imm)
{
    return enc_ext(EXT_LDI) | ((rd & 0x1Fu) << 19) | (imm & 0x7FFFFu);
}

static uint32_t enc_alu(uint32_t rd, uint32_t rs1, uint32_t rs2, uint32_t fn)
{
    return enc_ext(EXT_ALU_OP) | ((rd & 0x1Fu) << 19) | ((rs1 & 0x1Fu) << 14) |
           ((rs2 & 0x1Fu) << 9) | (fn & 0xFu);
}

/* ------------------------------------------------------------------ */
/* Montador (texto -> palavra de 32 bits)                              */
/* ------------------------------------------------------------------ */
static int parse_num(const char *s, long *out)
{
    char *end;
    long v;
    int base = 10;

    while (isspace((unsigned char)*s))
        s++;
    if (!*s)
        return -1;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        base = 16;
    v = strtol(s, &end, base);
    if (end == s)
        return -1;
    while (isspace((unsigned char)*end))
        end++;
    if (*end)
        return -1;
    *out = v;
    return 0;
}

/* Aceita "160", "0xA0", "x=160", "id2", "R1" e (se mirror_ok) H/V/HV */
static int tok_val(const char *t, int mirror_ok, long *out)
{
    const char *eq = strchr(t, '=');
    if (eq)
        t = eq + 1;
    else if ((t[0] == 'i' || t[0] == 'I') && (t[1] == 'd' || t[1] == 'D') &&
             isdigit((unsigned char)t[2]))
        t += 2;
    else if ((t[0] == 'r' || t[0] == 'R') && isdigit((unsigned char)t[1]))
        t += 1;

    if (mirror_ok) {
        if (!strcasecmp(t, "H")) { *out = 2; return 0; }
        if (!strcasecmp(t, "V")) { *out = 1; return 0; }
        if (!strcasecmp(t, "HV") || !strcasecmp(t, "VH")) { *out = 3; return 0; }
    }
    return parse_num(t, out);
}

static int is_hexword(const char *t)
{
    size_t n = strlen(t), i;
    if (n > 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) {
        if (n > 10)
            return 0;
        for (i = 2; i < n; i++)
            if (!isxdigit((unsigned char)t[i]))
                return 0;
        return 1;
    }
    if (n != 8)
        return 0;
    for (i = 0; i < n; i++)
        if (!isxdigit((unsigned char)t[i]))
            return 0;
    return 1;
}

/* Procura "hex = XXXXXXXX" no comentario (game_program.asm) */
static int find_expected(const char *c, uint32_t *exp)
{
    const char *p = strstr(c, "hex");
    char *end;
    unsigned long v;

    if (!p)
        return 0;
    p += 3;
    while (*p == ' ' || *p == '\t')
        p++;
    if (*p != '=')
        return 0;
    p++;
    while (*p == ' ' || *p == '\t')
        p++;
    v = strtoul(p, &end, 16);
    if (end - p != 8)
        return 0;
    *exp = (uint32_t)v;
    return 1;
}

static int get_args(char **t, int n, int k, int mirror_idx, long *v, char *err, size_t en)
{
    int i;
    if (n - 1 != k) {
        snprintf(err, en, "%s espera %d argumento(s), recebeu %d", t[0], k, n - 1);
        return -1;
    }
    for (i = 0; i < k; i++) {
        if (tok_val(t[1 + i], i == mirror_idx, &v[i]) < 0) {
            snprintf(err, en, "argumento invalido: '%s'", t[1 + i]);
            return -1;
        }
    }
    return 0;
}

static int rng(long v, const char *name, long hi, char *err, size_t en)
{
    if (v < 0 || v > hi) {
        snprintf(err, en, "%s fora da faixa 0..%ld (recebeu %ld)", name, hi, v);
        return -1;
    }
    return 0;
}

static const struct { const char *m; uint32_t w; } k_noarg[] = {
    {"NOP", 0x00000000u},    {"CLEAR", 0x20000000u}, {"RECT", 0x50000000u},
    {"TRI", 0x60000000u},    {"MIRROR", 0xA0000000u}, {"ERS_BACK", 0x01000000u},
    {"HALT", 0xF0000000u},
};
static const struct { const char *m; uint32_t op; } k_xy[] = {
    {"XY", OP_XY}, {"WH", OP_WH}, {"T1", OP_T1}, {"T2", OP_T2},
    {"SET_SCROLL", OP_SET_SCROLL}, {"MV_SCROLL", OP_MV_SCROLL},
};
static const struct { const char *m; uint32_t fn; } k_alu[] = {
    {"ADD", 0}, {"SUB", 1}, {"AND", 2}, {"OR", 3}, {"XOR", 4}, {"SLL", 5}, {"SRL", 6},
};

/*
 * Retorno: 0 = ok (palavra em *w), 1 = linha vazia/comentario, -1 = erro (msg em err).
 * Se a linha tiver "; hex = XXXXXXXX", *has_exp=1 e *exp recebe o valor esperado.
 */
static int assemble_line(const char *src, uint32_t *w, int *has_exp, uint32_t *exp,
                         char *err, size_t en)
{
    char buf[256];
    char *tok[10];
    char **t;
    char *p, *sc;
    int n = 0, i;
    long v[6];

    *has_exp = 0;
    snprintf(buf, sizeof buf, "%s", src);
    sc = strchr(buf, ';');
    if (sc) {
        *has_exp = find_expected(sc + 1, exp);
        *sc = 0;
    }
    for (p = strtok(buf, " \t,\r\n"); p && n < 10; p = strtok(NULL, " \t,\r\n"))
        tok[n++] = p;
    t = tok;
    if (n > 0 && t[0][strlen(t[0]) - 1] == ':') { /* rotulo "00:" */
        t++;
        n--;
    }
    if (n == 0)
        return 1;

    if (n == 1 && is_hexword(t[0])) { /* linha de .hex */
        *w = (uint32_t)strtoul(t[0], NULL, 16);
        return 0;
    }

    for (p = t[0]; *p; p++)
        *p = (char)toupper((unsigned char)*p);

    for (i = 0; i < ARRAY_LEN(k_noarg); i++) {
        if (!strcmp(t[0], k_noarg[i].m)) {
            if (get_args(t, n, 0, -1, v, err, en) < 0)
                return -1;
            *w = k_noarg[i].w;
            return 0;
        }
    }
    for (i = 0; i < ARRAY_LEN(k_xy); i++) {
        if (!strcmp(t[0], k_xy[i].m)) {
            if (get_args(t, n, 2, -1, v, err, en) < 0 ||
                rng(v[0], "x/w", 511, err, en) < 0 || rng(v[1], "y/h", 255, err, en) < 0)
                return -1;
            *w = enc_xy(k_xy[i].op, (uint32_t)v[0], (uint32_t)v[1]);
            return 0;
        }
    }
    for (i = 0; i < ARRAY_LEN(k_alu); i++) {
        if (!strcmp(t[0], k_alu[i].m)) {
            if (get_args(t, n, 3, -1, v, err, en) < 0 ||
                rng(v[0], "Rd", 31, err, en) < 0 || rng(v[1], "Rs1", 31, err, en) < 0 ||
                rng(v[2], "Rs2", 31, err, en) < 0)
                return -1;
            *w = enc_alu((uint32_t)v[0], (uint32_t)v[1], (uint32_t)v[2], k_alu[i].fn);
            return 0;
        }
    }

    if (!strcmp(t[0], "COLOR")) {
        if (get_args(t, n, 1, -1, v, err, en) < 0 || rng(v[0], "cor", 255, err, en) < 0)
            return -1;
        *w = enc_color((uint32_t)v[0]);
        return 0;
    }
    if (!strcmp(t[0], "SET_SPRITE")) { /* id x y mirror tile */
        if (get_args(t, n, 5, 3, v, err, en) < 0 || rng(v[0], "id", 31, err, en) < 0 ||
            rng(v[1], "x", 511, err, en) < 0 || rng(v[2], "y", 255, err, en) < 0 ||
            rng(v[3], "mirror", 3, err, en) < 0 || rng(v[4], "tile", 15, err, en) < 0)
            return -1;
        *w = enc_sprite(OP_SET_SPRITE, (uint32_t)v[0], (uint32_t)v[1], (uint32_t)v[2],
                        (uint32_t)v[3], (uint32_t)v[4]);
        return 0;
    }
    if (!strcmp(t[0], "MV_SPRITE")) { /* id x y */
        if (get_args(t, n, 3, -1, v, err, en) < 0 || rng(v[0], "id", 31, err, en) < 0 ||
            rng(v[1], "x", 511, err, en) < 0 || rng(v[2], "y", 255, err, en) < 0)
            return -1;
        *w = enc_sprite(OP_MV_SPRITE, (uint32_t)v[0], (uint32_t)v[1], (uint32_t)v[2], 0, 0);
        return 0;
    }
    if (!strcmp(t[0], "ERS_SPRITE")) { /* id */
        if (get_args(t, n, 1, -1, v, err, en) < 0 || rng(v[0], "id", 31, err, en) < 0)
            return -1;
        *w = enc_sprite(OP_ERS_SPRITE, (uint32_t)v[0], 0, 0, 0, 0);
        return 0;
    }
    if (!strcmp(t[0], "DFN_PRTY") || !strcmp(t[0], "MV_PRTY")) {
        if (get_args(t, n, 1, -1, v, err, en) < 0 || rng(v[0], "prioridade", 3, err, en) < 0)
            return -1;
        *w = enc_ext(t[0][0] == 'D' ? EXT_DFN_PRTY : EXT_MV_PRTY) | (uint32_t)v[0];
        return 0;
    }
    if (!strcmp(t[0], "LDI")) { /* Rd, imm */
        if (get_args(t, n, 2, -1, v, err, en) < 0 || rng(v[0], "Rd", 31, err, en) < 0 ||
            rng(v[1], "imm", 0x7FFFF, err, en) < 0)
            return -1;
        *w = enc_ldi((uint32_t)v[0], (uint32_t)v[1]);
        return 0;
    }
    if (!strcmp(t[0], "ALU_OP")) { /* Rd, Rs1, Rs2, func */
        if (get_args(t, n, 4, -1, v, err, en) < 0 || rng(v[0], "Rd", 31, err, en) < 0 ||
            rng(v[1], "Rs1", 31, err, en) < 0 || rng(v[2], "Rs2", 31, err, en) < 0 ||
            rng(v[3], "func", 15, err, en) < 0)
            return -1;
        *w = enc_alu((uint32_t)v[0], (uint32_t)v[1], (uint32_t)v[2], (uint32_t)v[3]);
        return 0;
    }

    snprintf(err, en, "mnemonico desconhecido: %s", t[0]);
    return -1;
}

/* ------------------------------------------------------------------ */
/* Entrada de dados                                                    */
/* ------------------------------------------------------------------ */
/* 0 = ok, 1 = interrompido (Ctrl+C); EOF encerra o programa */
static int read_line(const char *prompt, char *buf, size_t n)
{
    size_t l;
    printf("%s", prompt);
    fflush(stdout);
    if (!fgets(buf, (int)n, stdin)) {
        if (g_stop) {
            g_stop = 0;
            clearerr(stdin);
            printf("\n");
            buf[0] = 0;
            return 1;
        }
        printf("\n");
        exit(0);
    }
    l = strlen(buf);
    while (l && (buf[l - 1] == '\n' || buf[l - 1] == '\r'))
        buf[--l] = 0;
    return 0;
}

/* Retorna o valor, ou -1 se cancelado ('q' ou Ctrl+C). def < 0 = sem padrao. */
static long ask_num(const char *label, long lo, long hi, long def)
{
    char buf[64], prompt[128];
    long v;
    for (;;) {
        if (def >= 0)
            snprintf(prompt, sizeof prompt, "  %s [%ld..%ld, enter=%ld, q=cancela]: ", label, lo, hi, def);
        else
            snprintf(prompt, sizeof prompt, "  %s [%ld..%ld, q=cancela]: ", label, lo, hi);
        if (read_line(prompt, buf, sizeof buf))
            return -1;
        if (!strcmp(buf, "q") || !strcmp(buf, "Q"))
            return -1;
        if (!buf[0] && def >= 0)
            return def;
        if (parse_num(buf, &v) == 0 && v >= lo && v <= hi)
            return v;
        puts("  valor invalido (decimal ou 0x..)");
    }
}

#define ASK(var, label, lo, hi, def)            \
    do {                                        \
        (var) = ask_num(label, lo, hi, def);    \
        if ((var) < 0) {                        \
            puts("  cancelado");                \
            return;                             \
        }                                       \
    } while (0)

#define TRY(call)                \
    do {                         \
        if ((call) < 0)          \
            return;              \
    } while (0)

/* ------------------------------------------------------------------ */
/* Execucao de listas de instrucoes (demos / arquivos)                 */
/* ------------------------------------------------------------------ */
static int run_asm(const char *const *lines, int n, unsigned delay_ms)
{
    int i;
    for (i = 0; i < n && !g_stop; i++) {
        uint32_t w, exp;
        int has_exp;
        char err[96];
        int r = assemble_line(lines[i], &w, &has_exp, &exp, err, sizeof err);
        if (r < 0) {
            printf("  ERRO em '%s': %s\n", lines[i], err);
            return -1;
        }
        if (r == 1)
            continue;
        if (gpu_send_t(lines[i], w) < 0)
            return -1;
        msleep(delay_ms);
    }
    return 0;
}

static const char *const D_POLY[] = {
    "CLEAR", "COLOR 0xFC", "XY 250,20", "WH 30,30", "RECT",
    "COLOR 0xE0", "XY 100,40", "T1 150,100", "T2 50,100", "TRI",
    "COLOR 0xFF", "XY 50,20", "WH 60,15", "RECT",
    "COLOR 0x1C", "XY 120,90", "WH 40,20", "RECT",
};
static const char *const D_BG[] = {
    "SET_SCROLL 0,0", "ERS_BACK", "SET_SCROLL 0,0", "MV_SCROLL 80,0",
};
static const char *const D_SPR[] = {
    "SET_SPRITE id0 x=160 y=150 mirror=0 tile=0",
    "SET_SPRITE id1 x=40 y=150 mirror=H tile=4",
    "SET_SPRITE id2 x=280 y=150 mirror=0 tile=0",
    "MV_SPRITE id0 x=200 y=120",
    "ERS_SPRITE id2",
};
static const char *const D_PRTY[] = {
    "DFN_PRTY 0", "DFN_PRTY 1", "DFN_PRTY 2", "DFN_PRTY 3", "DFN_PRTY 0",
};
static const char *const D_ALU[] = {
    "LDI R1, 10", "ADD R2, R1, R1",
};

static void load_file(const char *path, unsigned delay_ms)
{
    FILE *f = fopen(path, "r");
    char line[256];
    int lineno = 0, bad = 0, checked = 0, mism = 0;
    unsigned long before = g_sent;

    if (!f) {
        perror(path);
        return;
    }
    printf("  carregando %s ...\n", path);
    while (fgets(line, sizeof line, f) && !g_stop) {
        uint32_t w, exp = 0;
        int has_exp, r;
        char err[96], *nl;

        lineno++;
        nl = strpbrk(line, "\r\n");
        if (nl)
            *nl = 0;
        r = assemble_line(line, &w, &has_exp, &exp, err, sizeof err);
        if (r == 1)
            continue;
        if (r < 0) {
            printf("  linha %d: %s\n", lineno, err);
            bad++;
            continue;
        }
        if (has_exp) {
            checked++;
            if (exp != w) {
                mism++;
                printf("  linha %d: DIVERGE montado=0x%08X esperado=0x%08X\n", lineno, w, exp);
            }
        }
        if (w == 0)
            continue;
        {
            char txt[64];
            char *sc = strchr(line, ';');
            if (sc)
                *sc = 0;
            snprintf(txt, sizeof txt, "%s", line);
            if (gpu_send_t(txt, w) < 0)
                break;
        }
        msleep(delay_ms);
    }
    fclose(f);
    printf("  arquivo: %lu palavra(s) enviada(s), %d erro(s) de sintaxe", g_sent - before, bad);
    if (checked)
        printf(", conferidas %d contra 'hex =' (%d divergencia(s))", checked, mism);
    printf("\n");
    g_stop = 0;
    finish();
}

/* ------------------------------------------------------------------ */
/* Acoes do menu                                                       */
/* ------------------------------------------------------------------ */
static void act_clear(void)
{
    TRY(gpu_send_t("CLEAR", enc_op(OP_CLEAR)));
    finish();
}

static void act_rect(void)
{
    long c, x, y, w, h;
    ASK(c, "cor (0..255, 0xFC=amarelo)", 0, 255, 0xFC);
    ASK(x, "x", 0, 511, 100);
    ASK(y, "y", 0, 255, 60);
    ASK(w, "largura", 0, 511, 40);
    ASK(h, "altura", 0, 255, 30);
    TRY(gpu_send_t("COLOR", enc_color((uint32_t)c)));
    TRY(gpu_send_t("XY", enc_xy(OP_XY, (uint32_t)x, (uint32_t)y)));
    TRY(gpu_send_t("WH", enc_xy(OP_WH, (uint32_t)w, (uint32_t)h)));
    TRY(gpu_send_t("RECT", enc_op(OP_RECT)));
    finish();
}

static void act_tri(void)
{
    long c, x0, y0, x1, y1, x2, y2;
    ASK(c, "cor (0..255, 0xE0=vermelho)", 0, 255, 0xE0);
    ASK(x0, "vertice 0 - x", 0, 511, 100);
    ASK(y0, "vertice 0 - y", 0, 255, 40);
    ASK(x1, "vertice 1 - x", 0, 511, 150);
    ASK(y1, "vertice 1 - y", 0, 255, 100);
    ASK(x2, "vertice 2 - x", 0, 511, 50);
    ASK(y2, "vertice 2 - y", 0, 255, 100);
    TRY(gpu_send_t("COLOR", enc_color((uint32_t)c)));
    TRY(gpu_send_t("XY (vertice 0)", enc_xy(OP_XY, (uint32_t)x0, (uint32_t)y0)));
    TRY(gpu_send_t("T1", enc_xy(OP_T1, (uint32_t)x1, (uint32_t)y1)));
    TRY(gpu_send_t("T2", enc_xy(OP_T2, (uint32_t)x2, (uint32_t)y2)));
    TRY(gpu_send_t("TRI", enc_op(OP_TRI)));
    finish();
}

static void act_sprite(void)
{
    char buf[16];
    long id, x, y, m, tile;

    puts("  1) SET_SPRITE   2) MV_SPRITE   3) ERS_SPRITE");
    if (read_line("  sprite> ", buf, sizeof buf))
        return;
    switch (buf[0]) {
    case '1':
        ASK(id, "id", 0, 31, 0);
        ASK(x, "x", 0, 511, 160);
        ASK(y, "y", 0, 255, 150);
        ASK(m, "espelho (0=nenhum 1=V 2=H 3=H+V)", 0, 3, 0);
        ASK(tile, "tile", 0, 15, 0);
        TRY(gpu_send_t("SET_SPRITE", enc_sprite(OP_SET_SPRITE, (uint32_t)id, (uint32_t)x,
                                                (uint32_t)y, (uint32_t)m, (uint32_t)tile)));
        break;
    case '2':
        ASK(id, "id", 0, 31, 0);
        ASK(x, "novo x", 0, 511, 200);
        ASK(y, "novo y", 0, 255, 120);
        TRY(gpu_send_t("MV_SPRITE", enc_sprite(OP_MV_SPRITE, (uint32_t)id, (uint32_t)x,
                                               (uint32_t)y, 0, 0)));
        break;
    case '3':
        ASK(id, "id", 0, 31, 0);
        TRY(gpu_send_t("ERS_SPRITE", enc_sprite(OP_ERS_SPRITE, (uint32_t)id, 0, 0, 0, 0)));
        break;
    default:
        return;
    }
    finish();
}

static void act_bg(void)
{
    char buf[16];
    long x, y;

    puts("  1) SET_SCROLL (liga fundo)   2) MV_SCROLL   3) ERS_BACK (desliga)");
    if (read_line("  fundo> ", buf, sizeof buf))
        return;
    switch (buf[0]) {
    case '1':
        ASK(x, "scroll x", 0, 511, 0);
        ASK(y, "scroll y", 0, 255, 0);
        TRY(gpu_send_t("SET_SCROLL", enc_xy(OP_SET_SCROLL, (uint32_t)x, (uint32_t)y)));
        break;
    case '2':
        ASK(x, "scroll x", 0, 511, 80);
        ASK(y, "scroll y", 0, 255, 0);
        TRY(gpu_send_t("MV_SCROLL", enc_xy(OP_MV_SCROLL, (uint32_t)x, (uint32_t)y)));
        break;
    case '3':
        TRY(gpu_send_t("ERS_BACK", enc_ext(EXT_ERS_BACK)));
        break;
    default:
        return;
    }
    finish();
}

static void act_prty(void)
{
    long p;
    puts("  0 = Sprite > Poligono > Fundo (padrao)   demais valores: veja compositor.v");
    ASK(p, "prioridade", 0, 3, 0);
    TRY(gpu_send_t("DFN_PRTY", enc_ext(EXT_DFN_PRTY) | (uint32_t)p));
    finish();
}

static void act_alu(void)
{
    char buf[16];
    long rd, rs1, rs2, fn, imm;

    puts("  1) LDI Rd,imm   2) ALU_OP Rd,Rs1,Rs2,func");
    puts("  func: 0=ADD 1=SUB 2=AND 3=OR 4=XOR 5=SLL 6=SRL");
    puts("  obs.: os registradores nao tem leitura pelo HPS; confira por simulacao/SignalTap.");
    if (read_line("  ula> ", buf, sizeof buf))
        return;
    switch (buf[0]) {
    case '1':
        ASK(rd, "Rd", 0, 31, 1);
        ASK(imm, "imediato (19 bits)", 0, 0x7FFFF, 10);
        TRY(gpu_send_t("LDI", enc_ldi((uint32_t)rd, (uint32_t)imm)));
        break;
    case '2':
        ASK(rd, "Rd", 0, 31, 2);
        ASK(rs1, "Rs1", 0, 31, 1);
        ASK(rs2, "Rs2", 0, 31, 1);
        ASK(fn, "func", 0, 15, 0);
        TRY(gpu_send_t("ALU_OP", enc_alu((uint32_t)rd, (uint32_t)rs1, (uint32_t)rs2, (uint32_t)fn)));
        break;
    default:
        return;
    }
    finish();
}

static void act_raw(void)
{
    char buf[64];
    long v;
    if (read_line("  palavra hex (ex.: 20000000): ", buf, sizeof buf) || !buf[0])
        return;
    if (!is_hexword(buf)) {
        const char *p = buf;
        if (parse_num(p, &v) < 0) {
            puts("  valor invalido");
            return;
        }
    } else {
        v = (long)strtoul(buf, NULL, 16);
    }
    TRY(gpu_send_t("RAW", (uint32_t)v));
    finish();
}

static void act_halt(void)
{
    char buf[8];
    puts("  HALT trava a control_unit ate o reset (KEY0).");
    if (read_line("  enviar mesmo assim? [s/N]: ", buf, sizeof buf) || (buf[0] != 's' && buf[0] != 'S'))
        return;
    g_allow_halt = 1;
    (void)gpu_send_t("HALT", enc_op(OP_HALT));
    g_allow_halt = 0;
    finish();
}

static void asm_help(void)
{
    puts("  CLEAR | COLOR c | XY x,y | WH w,h | RECT | T1 x,y | T2 x,y | TRI");
    puts("  SET_SPRITE id x y mirror tile | MV_SPRITE id x y | ERS_SPRITE id");
    puts("  SET_SCROLL x,y | MV_SCROLL x,y | ERS_BACK | DFN_PRTY p | MV_PRTY p");
    puts("  LDI Rd,imm | ADD/SUB/AND/OR/XOR/SLL/SRL Rd,Rs1,Rs2 | ALU_OP Rd,Rs1,Rs2,f");
    puts("  NOP | HALT (bloqueado) | palavra hex crua (8 digitos)");
    puts("  numeros: decimal ou 0x..;  aceita 'x=160', 'id2', 'R1', 'mirror=H'");
}

static void act_asm(void)
{
    char buf[256];
    puts("  Modo assembly. 'help' lista as instrucoes, 'q' volta ao menu.");
    for (;;) {
        uint32_t w, exp;
        int has_exp, r;
        char err[96];

        if (read_line("  asm> ", buf, sizeof buf) || !strcmp(buf, "q"))
            break;
        if (!strcmp(buf, "help") || !strcmp(buf, "?")) {
            asm_help();
            continue;
        }
        r = assemble_line(buf, &w, &has_exp, &exp, err, sizeof err);
        if (r == 1)
            continue;
        if (r < 0) {
            printf("  ERRO: %s\n", err);
            continue;
        }
        (void)gpu_send_t(buf, w);
    }
    finish();
}

static void act_load(void)
{
    char path[200], buf[16];
    long d;
    if (read_line("  arquivo (.asm ou .hex): ", path, sizeof path) || !path[0])
        return;
    ASK(d, "pausa entre instrucoes (ms)", 0, 5000, 0);
    if (read_line("  enviar HALT do arquivo? [s/N]: ", buf, sizeof buf))
        return;
    g_allow_halt = (buf[0] == 's' || buf[0] == 'S');
    load_file(path, (unsigned)d);
    g_allow_halt = 0;
}

static void act_demos(void)
{
    char buf[16];
    long d;

    puts("  1) Poligonos (sol, triangulo, nuvem, retangulo)");
    puts("  2) Fundo: liga / desliga / religa / reposiciona");
    puts("  3) Sprites: cria 3, move 1, apaga 1");
    puts("  4) Prioridade do compositor 0..3");
    puts("  5) Registradores / ULA (LDI + ADD)");
    puts("  6) Programa completo (game_program.asm sem HALT)");
    if (read_line("  demo> ", buf, sizeof buf))
        return;
    if (buf[0] < '1' || buf[0] > '6')
        return;
    ASK(d, "pausa entre instrucoes (ms)", 0, 5000, 300);
    g_stop = 0;
    switch (buf[0]) {
    case '1': TRY(run_asm(D_POLY, ARRAY_LEN(D_POLY), (unsigned)d)); break;
    case '2': TRY(run_asm(D_BG, ARRAY_LEN(D_BG), (unsigned)(d < 800 ? 800 : d))); break;
    case '3': TRY(run_asm(D_SPR, ARRAY_LEN(D_SPR), (unsigned)(d < 600 ? 600 : d))); break;
    case '4': TRY(run_asm(D_PRTY, ARRAY_LEN(D_PRTY), (unsigned)(d < 1500 ? 1500 : d))); break;
    case '5': TRY(run_asm(D_ALU, ARRAY_LEN(D_ALU), (unsigned)d)); break;
    case '6':
        TRY(run_asm(D_POLY, ARRAY_LEN(D_POLY), (unsigned)d));
        TRY(run_asm(D_BG, ARRAY_LEN(D_BG), (unsigned)d));
        TRY(run_asm(D_SPR, ARRAY_LEN(D_SPR), (unsigned)d));
        TRY(run_asm(D_PRTY, ARRAY_LEN(D_PRTY) - 4, (unsigned)d)); /* so o DFN_PRTY 0 */
        TRY(run_asm(D_ALU, ARRAY_LEN(D_ALU), (unsigned)d));
        break;
    }
    g_stop = 0;
    finish();
}

static void act_anim(void)
{
    char buf[16];
    long id, tile, y, d, x = 0;
    int dir = 1;

    puts("  1) Sprite vai-e-vem (MV_SPRITE)   2) Fundo rolando (MV_SCROLL)");
    if (read_line("  anim> ", buf, sizeof buf))
        return;
    if (buf[0] != '1' && buf[0] != '2')
        return;
    ASK(d, "pausa por quadro (ms)", 1, 1000, 15);
    g_stop = 0;

    if (buf[0] == '1') {
        ASK(id, "id do sprite", 0, 31, 0);
        ASK(tile, "tile", 0, 15, 0);
        ASK(y, "y", 0, 255, 150);
        TRY(gpu_send_t("SET_SPRITE", enc_sprite(OP_SET_SPRITE, (uint32_t)id, 0, (uint32_t)y, 0, (uint32_t)tile)));
        puts("  animando... Ctrl+C para parar");
        while (!g_stop) {
            x += 2 * dir;
            if (x >= 300) { x = 300; dir = -1; }
            if (x <= 0)   { x = 0;   dir = 1; }
            if (gpu_send_t(NULL, enc_sprite(OP_MV_SPRITE, (uint32_t)id, (uint32_t)x, (uint32_t)y, 0, 0)) < 0)
                break;
            msleep((unsigned)d);
        }
    } else {
        TRY(gpu_send_t("SET_SCROLL 0,0", enc_xy(OP_SET_SCROLL, 0, 0)));
        puts("  rolando... Ctrl+C para parar");
        while (!g_stop) {
            x = (x + 2) & 0x1FF;
            if (gpu_send_t(NULL, enc_xy(OP_MV_SCROLL, (uint32_t)x, 0)) < 0)
                break;
            msleep((unsigned)d);
        }
    }
    g_stop = 0;
    finish();
}

/* ------------------------------------------------------------------ */
static void banner(void)
{
    puts("");
    puts("  Coprocessador grafico - teste pelo HPS (LW bridge 0xFF200000)");
    puts("  pio_Cmd +0x00 (W) | pio_status +0x10 (R): [0]empty [1]full [2]busy [3]done");
    puts("  Requer active_mode = 1'b0 em control_unit_32.v (senao a FIFO e ignorada).");
}

static void menu(void)
{
    puts("");
    puts("==================== MENU GPU ====================");
    puts("  1) Limpar tela (CLEAR)        6) Prioridade (DFN_PRTY)");
    puts("  2) Retangulo                  7) Registradores / ULA");
    puts("  3) Triangulo                  8) Demos prontas");
    puts("  4) Sprite (SET/MV/ERS)        9) Animacoes");
    puts("  5) Fundo (SET/MV/ERS)         a) Terminal assembly");
    puts("  f) Carregar arquivo .asm/.hex r) Palavra hex crua");
    puts("  s) Status                     h) Enviar HALT");
    puts("  0) Sair");
}

int main(int argc, char **argv)
{
    char buf[32];
    struct sigaction sa;

    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_sigint; /* sem SA_RESTART: interrompe fgets/usleep */
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);

    if (hw_open() < 0)
        return 1;
    atexit(hw_close);

    hw_write(0); /* estado conhecido: pio_Cmd = 0 (NOP) */
    g_last = 0;

    banner();
    print_status();
    if (argc > 1)
        load_file(argv[1], 0);

    for (;;) {
        menu();
        if (read_line("> ", buf, sizeof buf))
            continue;
        g_stop = 0;
        switch (tolower((unsigned char)buf[0])) {
        case '1': act_clear(); break;
        case '2': act_rect(); break;
        case '3': act_tri(); break;
        case '4': act_sprite(); break;
        case '5': act_bg(); break;
        case '6': act_prty(); break;
        case '7': act_alu(); break;
        case '8': act_demos(); break;
        case '9': act_anim(); break;
        case 'a': act_asm(); break;
        case 'f': act_load(); break;
        case 'r': act_raw(); break;
        case 's': print_status(); break;
        case 'h': act_halt(); break;
        case '0':
        case 'q': return 0;
        default: break;
        }
    }
}

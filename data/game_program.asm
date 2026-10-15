; ============================================================
; game_program.asm - ISA ATUAL do control_unit_32 (HPS/FIFO)
; Opcode 0x7 = SET_SPRITE (o T0 antigo nao existe mais): o vertice 0
; do triangulo e o ultimo XY antes do TRI.
; Maximo 32 palavras (PC de 5 bits). Carregue com: ./run_program game_program.hex
; ============================================================

00: CLEAR                                         ; hex = 20000000   limpa o framebuffer dos poligonos (cor 0 = transparente)
01: COLOR 0xFC                                    ; hex = 100000FC   amarelo
02: XY 250,20                                     ; hex = 33E85000   posicao do sol
03: WH 30,30                                      ; hex = 40787800   tamanho do sol
04: RECT                                          ; hex = 50000000   desenha retangulo
05: COLOR 0xE0                                    ; hex = 100000E0   vermelho
06: XY 100,40                                     ; hex = 3190A000   vertice 0 do triangulo (o TRI le o ultimo XY)
07: T1 150,100                                    ; hex = 82599000   vertice 1
08: T2 50,100                                     ; hex = 90C99000   vertice 2
09: TRI                                           ; hex = 60000000   desenha triangulo
10: COLOR 0xFF                                    ; hex = 100000FF   branco
11: XY 50,20                                      ; hex = 30C85000   posicao da nuvem
12: WH 60,15                                      ; hex = 40F03C00   tamanho da nuvem
13: RECT                                          ; hex = 50000000   desenha retangulo
14: COLOR 0x1C                                    ; hex = 1000001C   verde
15: XY 120,90                                     ; hex = 31E16800
16: WH 40,20                                      ; hex = 40A05000
17: RECT                                          ; hex = 50000000   testa sobreposicao com o triangulo
18: SET_SCROLL 0,0                                ; hex = B0000000   liga o background (anda sozinho)
19: ERS_BACK                                      ; hex = 01000000   desliga o background
20: SET_SCROLL 0,0                                ; hex = B0000000   liga de novo
21: MV_SCROLL 80,0                                ; hex = E1400000   reposiciona o fundo
22: SET_SPRITE id0 x=160 y=150 mirror=0 tile=0    ; hex = 70282580   cavaleiro
23: SET_SPRITE id1 x=40 y=150 mirror=H tile=4     ; hex = 708A25A4   bloco verde espelhado
24: SET_SPRITE id2 x=280 y=150 mirror=0 tile=0    ; hex = 71462580   sprite temporario
25: MV_SPRITE id0 x=200 y=120                     ; hex = C0321E00   move o cavaleiro
26: ERS_SPRITE id2                                ; hex = D1000000   apaga o sprite temporario
27: DFN_PRTY 0                                    ; hex = 02000000   sprite > poligono > fundo
28: LDI R1, 10                                    ; hex = 0508000A   carrega R1 = 10 (testa Register File)
29: ADD R2, R1, R1                                ; hex = 04104200   calcula R2 = 10 + 10 = 20 (testa ULA)
30: HALT                                          ; hex = F0000000   fim

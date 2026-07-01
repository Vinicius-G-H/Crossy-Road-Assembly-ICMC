; Teste da instrucao OUTNUM
; Imprime o valor numerico decimal de um registrador
;
; Saida esperada:
;   0
;   42
;   100
;   65535
;   8  (resultado de operacao aritmetica: 3+5)

    ; Teste 1: Imprime zero
    loadn r0, #0
    outnum r0           ; Esperado: 0

    ; Newline para separar saidas
    loadn r1, #10       ; ASCII 10 = '\n'
    loadn r2, #0
    outchar r1, r2

    ; Teste 2: Valor direto
    loadn r0, #42
    outnum r0           ; Esperado: 42

    outchar r1, r2      ; newline

    ; Teste 3: Outro valor direto
    loadn r0, #100
    outnum r0           ; Esperado: 100

    outchar r1, r2      ; newline

    ; Teste 4: Valor maximo de 16 bits
    loadn r0, #65535
    outnum r0           ; Esperado: 65535

    outchar r1, r2      ; newline

    ; Teste 5: Resultado de soma (3 + 5 = 8)
    loadn r3, #3
    loadn r4, #5
    add r5, r3, r4
    outnum r5           ; Esperado: 8

    outchar r1, r2      ; newline

Fim:
    halt

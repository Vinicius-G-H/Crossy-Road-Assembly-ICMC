# Crossy-Road-Assembly-ICMC
Jogo estilo Crossy Road em Assembly para o Processador ICMC (Arquitetura RISC com 8 registradores). 
Projeto acadêmico focado em lógica de baixo nível, controle de periféricos, interrupções e renderização direta na memória de vídeo (tela de caracteres). 
Inclui movimentação do personagem, obstáculos em movimento e mecânica de colisões.

Link do video explicativo : https://youtu.be/5b9k3Nvf9kQ?si=3U_l4RjKIozARcJa

# Processador e funções:

## Preditor de Branch — Saturating Counter de 2 Bits

O simulador implementa um preditor de branch do tipo *saturating counter* de 2 bits, uma das técnicas clássicas de predição de desvio estudadas em arquitetura de computadores. O objetivo é antecipar, antes da execução de uma instrução de salto condicional (`JMP` ou `CALL`), se o branch será tomado ou não — informação que num pipeline real seria necessária para buscar a próxima instrução sem desperdiçar ciclos.

O preditor é composto por uma tabela chamada BHT (*Branch History Table*) com 64 entradas, cada uma armazenando um contador que varia entre 0 e 3. Esses quatro valores representam quatro estados: *Fortemente Não-Tomado* (0), *Fracamente Não-Tomado* (1), *Fracamente Tomado* (2) e *Fortemente Tomado* (3). A previsão é simples: se o contador da entrada for maior ou igual a 2, o preditor prevê que o branch será tomado; caso contrário, prevê que não será. A entrada da tabela usada é determinada pelo endereço do `PC` no momento do branch, calculado como `PC % 64`.

A cada branch executado, o contador é atualizado: se o branch foi tomado, o contador incrementa (saturando em 3); se não foi, decrementa (saturando em 0). O nome *saturating* vem exatamente desse comportamento — o valor não passa dos limites. A vantagem dos 2 bits sobre 1 bit é a robustez em loops: como é necessário errar duas vezes consecutivas para mudar de previsão, um loop que itera muitas vezes e depois termina erra apenas uma vez na saída, em vez de duas.

O relatório exibido ao final (No próprio simulador) da execução contabiliza todos os branches encontrados, quantas previsões foram corretas e a taxa de acerto em porcentagem. A contagem é feita comparando a previsão registrada *antes* da execução com o resultado real observado *depois* da avaliação das flags — garantindo que o preditor não "veja o futuro" na hora de contabilizar os acertos.

##Outnum

A instrução OUTNUM (opcode 54). 

#define OUTNUM 54 — declarado junto com as outras instruções de I/O.
case OUTNUM no STATE_DECODE — executa printf("%d", reg[rx]), imprimindo o valor numérico decimal do registrador Rx.

OUTCHAR imprime o caractere ASCII do valor (útil para texto), mas não há como imprimir um número diretamente — você precisaria converter manualmente para dígitos ASCII no assembly. OUTNUM resolve isso em uma instrução, o que é muito útil para debug.

# Mecânicas do Jogo 

## Movimentação do Jogador

A movimentação do jogador é controlada pela instrução `inchar r6`, que realiza a leitura do teclado de forma **não-bloqueante**: se nenhuma tecla foi pressionada no ciclo atual, a instrução simplesmente retorna zero em `r6` e o jogo segue adiante sem travar. Isso é fundamental para o funcionamento do game loop — o programa nunca fica esperando o jogador apertar uma tecla, ele apenas verifica se há alguma entrada disponível e, caso não haja, continua a atualizar os inimigos e redesenhar a tela. A posição do jogador é armazenada de forma separada em dois registradores fixos que persistem entre todas as iterações do loop: `r1` guarda a **coluna** atual (valor de 0 a 39) e `r2` guarda a **linha** atual (valor de 0 a 29). Essa escolha de manter a posição em registradores, e não em variáveis de memória, é uma otimização deliberada — registradores são acessados instantaneamente, sem custo de ciclo de memória, o que importa num processador simples como o ICMC onde cada instrução conta.

Após a leitura, o código faz uma cadeia de comparações (`cmp r6, r5` seguido de `jne`) para identificar qual tecla foi pressionada. As quatro teclas reconhecidas são `'w'`, `'a'`, `'s'` e `'d'`, correspondendo respectivamente aos movimentos para cima, esquerda, baixo e direita. Para o movimento horizontal (`'a'` e `'d'`), a lógica é direta: antes de alterar `r1`, o código verifica se o jogador já está no limite lateral — coluna 0 para a esquerda e coluna 39 para a direita. Se o limite já foi atingido, a instrução `jeq continua` desvia o fluxo para o fim do processamento de entrada sem modificar nada, garantindo que o jogador não "saia" da grade. Caso contrário, `r1` é incrementado (`inc r1`) ou decrementado (`dec r1`) em uma unidade, e o fluxo cai em `apaga_e_continua`, que cuida de limpar o caractere `'X'` da posição anterior antes da próxima renderização. Para o movimento vertical com `'s'` (para baixo), a lógica é análoga: o limite é a linha 29 (a última linha da grade), e se `r2` já vale 29, o movimento é ignorado.

O movimento para cima com `'w'` é o mais complexo e importante do jogo, pois carrega toda a lógica de progressão. Antes de qualquer coisa, o código verifica se `r2` (linha atual) é igual a zero. Se não for, trata-se de um movimento normal e simplesmente executa `dec r2`, subindo o jogador uma linha. Mas se `r2` já for zero — ou seja, o jogador já está na borda superior da tela e pressiona `'w'` novamente — ocorre o chamado **wrap vertical**, que é o evento central de progressão do jogo inteiro. Nesse caso, em vez de ignorar o movimento ou travar, o código dispara uma cascata de atualizações: incrementa a pontuação em 10, aumenta a velocidade global (`game_speed`), incrementa o contador de wraps (`wrap_vertical_cnt`), recalcula `extra_steps`, troca o mapa visual (`tela_atual`), redesenha a tela inteira chamando a função `printtela#Screen` correspondente, e finalmente reposiciona o jogador na linha 29 (de volta à base). Após qualquer movimento bem-sucedido, o fluxo sempre passa por `apaga_e_continua`, que usa a variável `pos_anterior` para saber exatamente onde o `'X'` estava no ciclo anterior e redesenhar o tile de fundo naquela posição, eliminando o rastro visual do jogador sem apagar o mapa.

---

## Declaração e Funcionamento dos Inimigos

O jogo contém **24 inimigos** distribuídos em 6 grupos de comportamento, cada grupo com 3 instâncias deslocadas horizontalmente entre si. Os grupos são: Y/Y2/Y3 (faixa das linhas 3–5, movem-se para a esquerda), Z/Z2/Z3 (linhas 7–9, para a direita), H/H2/H3 (linhas 11–13, para a direita), K-W/K2-W2/K3-W3 (linhas 17–19, para a esquerda, em pares), U-L/U2-L2/U3-L3 (linhas 1–2, para a direita, em pares) e Q/Q2/Q3 (linhas 22–24, para a direita). Cada inimigo individual é descrito por apenas **duas variáveis de memória**: `pos_X_inimigo`, que armazena sua posição linear atual na grade (um número de 0 a 1199), e `X_delay_cnt`, que é um contador de ciclos desde o último movimento. Não há estruturas de dados, não há arrays de objetos — cada inimigo é literalmente dois endereços de memória nomeados. A ausência de `MUL` e de estruturas compostas no ICMC força essa abordagem flat e repetitiva, onde o código para mover Y, Y2 e Y3 é essencialmente idêntico, apenas referenciando variáveis diferentes. Isso explica por que o arquivo tem quase 8000 linhas: é repetição necessária, não complexidade inerente.

Os pares **KW** e **UL** são casos especiais que merecem atenção. Nesses grupos, dois inimigos ocupam posições adjacentes e se movem de forma sincronizada: K é o "líder" e W sempre ocupa a posição `pos_K + 1`. O código de movimento calcula apenas a nova posição de K e depois deriva a posição de W com um simples `inc r0`, aplicando o wrap de faixa se necessário (se W "estourasse" para fora da faixa, ele é reposicionado no início). Visualmente, K e W aparecem como um obstáculo de largura 2 na grade, criando uma barreira mais difícil de desviar. O mesmo princípio se aplica a UL. Durante o apagamento, ambas as posições precisam ser limpas separadamente antes do movimento, o que significa que o bloco de código para KW executa dois ciclos completos de apagamento por frame de movimento — primeiro apaga K, depois apaga W.

O sistema de delay controla individualmente a velocidade de cada grupo. Cada inimigo tem um `base_delay` fixo: Y usa 1, Z usa 2, H usa 4, K/W usam 3, U/L usam 5 e Q usa 2. A cada ciclo do loop principal, o código incrementa o `delay_cnt` do inimigo e o compara com um threshold calculado dinamicamente: `threshold = base_delay - game_speed` (com mínimo de 1). Enquanto `delay_cnt < threshold`, o inimigo não se move — apenas o contador cresce. Quando `delay_cnt >= threshold`, o inimigo executa o ciclo completo de apaga-move-desenha e seu contador é zerado. No início do jogo (`game_speed = 0`), um inimigo com `base_delay = 4` só se move a cada 4 ciclos do loop, enquanto um com `base_delay = 1` se move a cada ciclo. Isso cria velocidades relativas visíveis: Y parece mais rápido que H no início. Conforme `game_speed` sobe, todos os thresholds diminuem, e eventualmente todos atingem 1 — movendo-se a cada ciclo. O `extra_steps` adiciona uma segunda camada de aceleração: quando vale 1, o inimigo dá 2 passos por ciclo de movimento em vez de 1; quando vale 2, dá 3 passos. Na prática isso significa que, em dificuldade máxima, um inimigo pode "pular" 3 colunas em um único ciclo de loop, tornando praticamente impossível prever sua trajetória por interpolação visual.

---

## Cálculo da Posição Linear

O simulador ICMC representa a tela como um vetor unidimensional de 1200 posições (30 linhas × 40 colunas = 1200), e a instrução `outchar` recebe exatamente um índice nesse vetor. Para converter a posição bidimensional do jogador (linha `r2`, coluna `r1`) num índice linear `r3`, é necessário calcular `r3 = r2 × 40 + r1`. O problema é que **o conjunto de instruções do ICMC não possui a instrução MUL**. A multiplicação precisa ser implementada manualmente, e a solução adotada é um loop de somas repetidas: acumula-se 40 em `r3` exatamente `r2` vezes, depois soma-se `r1` ao resultado. O trecho de código responsável por isso é o `multLoop`, que usa um contador auxiliar `r5` incrementado a cada iteração até atingir `r2`.

```
loadn r3, #0
loadn r5, #0
multLoop:
  cmp r5, r2
  jeq somaX       ; se r5 == r2, terminou as somas
  loadn r6, #40
add40:
  inc r3           ; soma 40 ao acumulador (um loop interno)
  dec r6
  jnz add40
  inc r5
  jmp multLoop
somaX:
  add r3, r3, r1   ; adiciona a coluna
```

Esse padrão de "multiplicar por somas" é uma solução clássica em arquiteturas sem multiplicador de hardware. No pior caso (jogador na linha 29), o loop interno `add40` executa 29 × 40 = 1160 iterações só para calcular a posição. Isso tem custo computacional relevante, mas é inevitável dado o conjunto de instruções disponível. Um detalhe importante: esse cálculo é feito **no início de cada ciclo do loop principal**, antes de qualquer outra operação, e o resultado é imediatamente salvo em `pos_anterior`. Isso garante que, independentemente de onde o jogador estiver, o sistema sempre sabe tanto a posição atual quanto a posição anterior para fins de apagamento.

Para os inimigos, o cálculo é mais simples porque suas posições são armazenadas diretamente como valores lineares desde a inicialização — não há conversão 2D→1D durante o jogo. Na inicialização, o código já define os valores iniciais no formato linear: por exemplo, `pos_y_inimigo = 120` corresponde exatamente à posição `linha 3, coluna 0` (3 × 40 + 0 = 120). O movimento incremental (`inc r0` ou `dec r0`) mantém esse valor no espaço linear, e o wrap horizontal garante que o valor nunca saia da faixa prevista para aquele grupo. Para acessar o tile de fundo no array estático da tela (durante o apagamento), usa-se `add r5, r5, r0` (base_tela + pos_linear) seguido de `loadi r5, r5` (leitura indireta do endereço calculado) — uma técnica de endereçamento indireto que simula acesso a array indexado.

---

## Detecção de Colisão

A detecção de colisão é implementada como uma **busca linear por igualdade de posição**: o código percorre os 24 inimigos em sequência, carrega a posição de cada um e a compara com a posição atual do jogador (`r3`). Se qualquer comparação resultar em igualdade, o fluxo desvia imediatamente para `game_over`. A elegância e a limitação dessa abordagem são a mesma coisa: ela é extremamente simples de implementar em Assembly (apenas `cmp` e `jeq`), mas exige que o código percorra todos os 24 inimigos a cada ciclo, mesmo que a colisão já tenha ocorrido no primeiro.

O código de colisão começa salvando os registradores que serão usados internamente (`push r0`, `push r4`, `push r5`) para não destruir o estado que o loop principal estava usando. Em seguida, inicializa um índice `r0 = 0` e um limite `r4 = 24`, e entra no `loop_colisao`. A cada iteração, o código compara `r0` com os valores 0 a 23 para determinar qual variável de posição carregar — como o ICMC não permite acesso a endereços calculados dinamicamente com facilidade para variáveis nomeadas não contíguas, o código usa uma longa cadeia de `cmp/jeq` que funciona como um `switch`. Cada case (`col_y`, `col_z`, etc.) executa `load r5, pos_X_inimigo` e salta para o label `compara`, que faz `cmp r3, r5` e, se iguais, pula para `game_over`. Se não for colisão, incrementa `r0` e repete o loop.

Uma consequência arquitetural importante: a verificação de colisão acontece **antes** de desenhar o jogador na nova posição. Isso significa que o jogo detecta se a posição calculada já está ocupada por um inimigo antes de colocar o `'X'` lá — o que é a semântica correta. Um detalhe adicional: como os inimigos KW e UL são pares que ocupam posições adjacentes, ambas as posições (`pos_k` e `pos_w`, `pos_u` e `pos_l`) são verificadas de forma independente no loop de colisão — tratadas como 24 inimigos individuais, não 18 + 3 pares. Isso garante que encostar em qualquer célula de um par seja detectado como colisão.

Quando `game_over` é alcançado, os três registradores salvos na pilha precisam ser desempilhados antes de qualquer outra coisa (`pop r5`, `pop r4`, `pop r0`), caso contrário o estado da pilha ficaria corrompido para a reinicialização via `jmp main`. Esse cuidado com o gerenciamento da pilha é um dos aspectos mais sutis do código e reflete boa prática de programação em baixo nível, mesmo que o contexto seja um jogo simples.

---

## Wraps Horizontais e Verticais, e Limites de Tela

**Wrap horizontal** é o mecanismo que faz os inimigos "reaparecerem" do lado oposto da tela quando saem pela borda. Cada grupo de inimigos tem uma faixa horizontal restrita, definida pelos limites inferior e superior de posição linear para aquela faixa. Por exemplo, o inimigo Y ocupa a linha 3 da grade, cuja faixa vai da posição 120 (linha 3, coluna 0) até a posição 159 (linha 3, coluna 39). Como Y se move para a esquerda (decrementa a posição a cada passo), o código verifica após cada `dec r0` se o valor atingiu 119 — que seria a posição imediatamente antes do início da faixa (linha 2, coluna 39), fora da faixa do Y. Quando isso acontece, a posição é forçada para 159 (extremo direito da faixa), fazendo o inimigo reaparecer do outro lado. O mesmo princípio se aplica aos inimigos que se movem para a direita, mas com a verificação no limite superior: Z, por exemplo, tem faixa 280–319 (linha 7), e quando atinge 320, é reposicionado em 280.

O wrap dos pares KW e UL exige atenção especial porque o seguidor (W ou L) sempre ocupa a posição `líder + 1`. Quando o líder está na última posição da faixa (por exemplo, K na posição 719 da faixa 680–719) e avança um passo para a esquerda chegando a 718, o seguidor W vai para 719 — tudo normal. Mas quando K está em 680 (início da faixa, movendo-se para a esquerda) e decrementa para 679 (fora da faixa), o código reposiciona K em 719. Então W seria K + 1 = 720 — que também está fora da faixa. O código trata esse caso com uma verificação extra: `se W >= 720, W = 680`, mantendo o seguidor dentro dos limites mesmo no momento do wrap do líder.

O `extra_steps` adiciona um terceiro nível de complexidade ao wrap horizontal. Quando `extra_steps >= 1`, o código executa um segundo `dec r0` (ou `inc r0`) após o primeiro, verificando o wrap novamente antes do segundo passo. Quando `extra_steps == 2`, executa um terceiro passo com mais uma verificação. Isso significa que a lógica de wrap é verificada até 3 vezes por ciclo de movimento, garantindo que não importa quantos passos o inimigo dê, ele sempre permanece dentro de sua faixa.

**Limites laterais do jogador** são tratados de forma diferente dos wraps dos inimigos: em vez de fazer wrap, o jogador simplesmente não se move. Antes de qualquer incremento ou decremento de `r1`, o código verifica explicitamente se já está no limite (`cmp r1, #39` para direita, `cmp r1, #0` para esquerda) e desvia para `continua` se for o caso. O mesmo vale para o limite inferior: na linha 29, pressionar `'s'` não faz nada. Isso cria uma "parede" invisível nas bordas esquerda, direita e inferior da tela que confina o jogador à grade jogável.

**Wrap vertical** é conceitualmente diferente de tudo o que foi descrito até agora — não é um comportamento de inimigo, mas o **mecanismo de progressão do jogo**. Quando o jogador está na linha 0 (topo da tela) e pressiona `'w'`, o código não bloqueia o movimento nem faz wrap simétrico: ele interpreta esse evento como "o jogador atravessou a tela inteira de baixo para cima com sucesso" e desencadeia toda a progressão: +10 na pontuação, `game_speed += 2`, incremento de `wrap_vertical_cnt`, recálculo do `extra_steps` baseado em `wrap_vertical_cnt`, alternância do mapa (índice `tela_atual` cicla 0→1→2→3→0), redesenho completo da nova tela chamando `call printtela#Screen`, e reposicionamento do jogador em `r2 = 29` (volta à base). Os inimigos **não são resetados** — eles continuam exatamente onde estavam, apenas agora se movem mais rápido por causa do `game_speed` aumentado. O mapa trocado é puramente visual (background diferente), pois as faixas dos inimigos são as mesmas em todos os mapas.

A borda superior da tela (linha 0) tem portanto um papel duplo no design do jogo: é tanto o destino que o jogador precisa atingir para pontuar quanto o gatilho de dificuldade crescente. Quanto mais vezes o jogador atravessa essa borda, mais rápido o jogo fica — de forma escalonada, com boosts maiores a cada faixa de wraps acumulados (0–10 wraps dão +3 de speed bônus, 11–15 dão +6, 16+ dão +10). Não existe uma condição de "você ganhou" — o jogo é projetado para ficar impossível eventualmente, e a pontuação final é a métrica de desempenho do jogador.

# Cenas do Claudinho

Vinhetas curtas que tocam por cima das animações de estado, inspiradas na tela vazia da aba **Code** do app mobile do Claude (gravação de 16/11/2026, 20 s, 60 fps).

## O que o vídeo mostra

| # | Trecho | O que acontece | Rótulo |
|---|---|---|---|
| 1 | 0–7 s | De perfil, digitando num notebook; vira de frente | **Comprovado** (quadros 0,5 / 6,4 / 7,0 s). O widget já tem isso no Codando |
| 2 | 7,8–9,2 s | O rabisco do fundo vira um **plugue**; o bichinho olha, aperta os olhos e inclina a cabeça | **Comprovado**: a sequência de poses e o plugue. **Hipótese**: que o plugue queira dizer "feature conectada". O que confirmaria: outra gravação com a frase destacada em outro idioma |
| 3 | 9,2–11,8 s | **Joaninha vermelha** entra pela esquerda; ele olha, agacha, dá um tapa com o braço esticado; ela vira e foge | **Comprovado** (quadros 9,4 a 11,8 s) |
| 4 | 12,4–14,6 s | Dá um passo para a esquerda, um **quadro verde-claro com cavalete** gira para dentro, ele escreve "7-3 ?" com um **pincel roxo**; o quadro gira para fora | **Comprovado** (pincel roxo visível em 14,0 s) |
| 5 | 15–19 s | Ao puxar a tela para baixo, ele aparece numa faixa de cima balançando/virando e depois volta | **Comprovado**: o gesto e o balanço. **Hipótese**: que seja o pull-to-refresh do app |
| — | 8,2 / 9,4 / 12,4 s | A frase "build a feature / fix a bug / explain your code" fica laranja no trecho da cena que está tocando | **Comprovado**: liga cada cena a um significado (plugue = feature, inseto = bug, quadro = explicar) |
| — | tempos exatos | Amostras a cada 0,2 s | **Hipótese**: ±0,2 s; os quadros-chave em `cenas.ps1` são aproximados |

## Como cada cena entra no Claudinho

| Cena | Gatilho | Por quê |
|---|---|---|
| `inseto` | uma ferramenta da conversa principal falhou (`failAt` novo, `classic.PostToolUseFailure`) | "fix a bug". Hoje a falha só aparece no histórico |
| `quadro` (em laço) | waiting em alerta com `askKind` igual a `pergunta` (AskUserQuestion) ou `plano` (ExitPlanMode); sai girando quando você responde | "explain": o "?" pisca enquanto ele espera. Permissão (`permissao`) continua com o pulo de braços para cima |
| `plugue` | entrada em ✅ Terminou | "build a feature": feature pronta |
| `pendurado` → `aterrissa` | arrastar o widget na vertical; ao soltar ele agacha e quica | equivalente ao "puxar a tela" |
| `aguardando` | subagente ativo (`agentsN > 0`) com a conversa principal fora de alerta e de erro: durante a ferramenta Agent o principal fica em Codando/Pensando, e com o subagente em segundo plano o estado exibido é "Agentes" (ver README) | "esperando o subagente": bate o pé olhando de lado a lado, com uma bolinha rosa (`$SUBC`) orbitando por subagente (máx. 3, acompanha `agentsN` ao vivo) e uma ampulheta que vira a cada 2 s; ao acabar as bolinhas voam para ele e ele pula. Substitui o notebook do Codando enquanto durar |
| rodízio | Ocioso ou Sua vez, sem cena tocando: uma de `plugue / inseto / quadro` a cada 40 a 80 s, sem repetir seguida | a tela vazia do app faz isso sem parar; aqui fica espaçado para não distrair (**Hipótese**: ajuste os intervalos depois de usar) |

Regras:
- Prioridade: arrasto (3) > quadro (2) > aguardando (1,5) > inseto/plugue (1). Inseto/plugue não interrompem a aguardando; quando acabam e ainda há subagentes ela volta, e o rodízio do ocioso não toca enquanto houver subagentes. Uma cena não interrompe outra de prioridade igual ou maior.
- Quando a família do modo muda (ocupado ↔ calmo ↔ alerta ↔ erro), a cena em curso sai (o quadro sai girando; as outras somem). O ❌ Erro continua com o tremor de olhos em X.
- Se a cena interrompeu o Codando, ele volta direto para o notebook (sem repetir a introdução).
- **Redução de movimento:** não toca nenhuma cena, exceto o quadro da pergunta e a aguardando, que aparecem paradas (informam algo: bolinhas fixas, sem bater o pé nem ampulheta girando). No modo reduzido (bolinha) a aguardando mostra só as bolinhas, sem ampulheta.
- Uma falha de ferramenta com mais de 8 s não vira inseto (evita tocar ao abrir o widget).

## Arquivos

| Arquivo | Mudança |
|---|---|
| `widget/cenas.ps1` (novo) | cena `aguardando` (gatilho 5b, quadros-chave e `CN-Aguardando`); motor (quadros-chave, fases entra/laço/sai, prioridades, gatilhos, rodízio, arrasto) e desenho dos adereços |
| `widget/claudinho-widget.ps1` | carrega `cenas.ps1`; `Draw-Mascot` aceita a pose da cena (`lift`, `reachL`, `marker`, `tilt`, olhos `squint`) e desenha os adereços em duas camadas; Paint chama `Cena-Gatilhos` + `Cena-Passo`; cena ativa = 30 fps; mouse alimenta a velocidade do arrasto; `Update-View` lê `failAt` e `askKind` |
| `types/index.d.ts`, `hooks/register.tsx` | `Mode` ganha `agents` (estado exibido derivado: Sua vez/Ocioso com subagente rodando; o Ocioso de 2 min não dispara); `St` ganha `failAt` e `askKind` (tag do atom `st-7` → `st-8`); publicados no JSON |

Para mexer: os quadros-chave estão na tabela `$script:CENAS` (cada quadro vale **até** o instante `ate`); cena nova = entrada na tabela + função de adereço em `Cena-Props` + gatilho em `Cena-Gatilhos`.

## Como testar no Windows

1. `claude plugin validate <pasta>`: passou aqui com os mesmos avisos que já existiam.
2. Ver uma cena em laço sem depender do Claude: `set CW_CENA=inseto` (ou `quadro`, `plugue`) e rode `powershell -STA -File widget\claudinho-widget.ps1`.
3. Em uso real: peça algo que faça um `Bash` falhar (inseto), peça para o Claude te fazer uma pergunta com AskUserQuestion (quadro), espere um turno terminar (plugue), arraste o widget (pendurado).
4. `CW_CENAS=0` desliga tudo.

**Não rastreável daqui:** como fica no Windows de verdade (DPI, ClearType, custo por quadro do PowerShell 5.1). A lógica e o desenho foram conferidos num simulador (PowerShell 7 no Linux com um `Graphics` falso que grava os retângulos), que gerou `cenas-preview.gif`. WinForms e GDI+ não rodaram.

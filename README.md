# Claudinho: mod do Claude Code com mascote e status do agente

Mod para o Claude Code que mostra, em tempo real, **o que o agente está fazendo** e **o uso da sessão**.
O mascote em pixel art (um bichinho laranja visto de lado, no estilo do app do Claude) muda de animação conforme o estado.
Ele aparece num **notch preto fixo na borda direita da tela** (sempre no topo) e também numa **linha de status** dentro do Claude Code.
O notch tem o mascote com um anel de estado e, abaixo dele, linhas de uso (limites de 5 h e 7 dias, contexto e subagentes); ao passar o mouse num item abre um balão com os detalhes.

> Foi construído com a skill `plugin-authoring` do Claude Code (mods por hooks). Se for continuar em outra sessão, peça para o Claude ler este README e a pasta `hooks/`.

## Como é composto

```
claudinho-panel/
├─ .claude-plugin/plugin.json   manifesto do mod
├─ hooks/
│  ├─ hooks.json                aponta para o módulo de hooks
│  ├─ register.tsx              hooks, estado, escrita do JSON, comando /claudinho
│  └─ mascots.ts                paletas dos mascotes (coral, azul, verde)
├─ types/index.d.ts             contrato do estado ($.state) do mod
└─ widget/
   ├─ claudinho-widget.ps1      widget "sempre no topo" (PowerShell + WinForms/GDI+)
   └─ iniciar-widget.cmd        abre o widget sem janela de console
```

Fluxo: **hooks do Claude Code → `register.tsx` atualiza o estado e grava `claudinho-state.json` na pasta do mod → `claudinho-widget.ps1` lê o JSON e anima o mascote e as linhas de uso.**
O widget só relê o arquivo quando ele muda; toda a animação (30 fps, 60 fps ao mudar a altura da faixa) é calculada por tempo dentro do widget.

## Qual hook alimenta qual estado

| Hook | Efeito |
|---|---|
| `prompt.submit` | 🧠 **Pensando** (zera o relógio do turno) |
| `tool.call` (Edit, Write, Bash, PowerShell, outros) | 💻 **Codando** e conta a ferramenta (top 5, histórico) |
| qualquer evento de **subagente** (`agentId` / `agent_id`) | não troca o estado do mascote: a ferramenta só é contada e entra no histórico com `↳`. Exceção: pedido de permissão de subagente ainda vira 🟡, e a ferramenta seguinte dele devolve o estado da conversa principal |
| `tool.call` (Read, Grep, Glob, LS, WebSearch, WebFetch) | 🔍 **Lendo/pesquisando** (cor própria, roxa) |
| `tool.call` (AskUserQuestion, ExitPlanMode) | 🟡 **Aguardando você** (em alerta) |
| `classic.PermissionRequest` | 🟡 **Aguardando você** (em alerta: precisa de permissão) |
| `classic.Notification` | 🟡 **Aguardando você** (em alerta, exceto `idle_prompt`) |
| `classic.PostToolUse` | volta a 🧠 Pensando; mantém Codando/Lendo visível por pelo menos 1,5 s |
| `classic.PostToolUseFailure` | ❌ **Erro** por 4 s |
| `classic.Stop` | ✅ **Terminou** por 4 s, depois 💬 **Sua vez** (neutro, sem alerta) |
| `turn.complete` | acumula tokens, lê contexto % e custo |
| timer de 1 s | 2 min sem atividade viram 😴 **Ocioso**; fim do flash de ✅/❌; relê os limites de uso 1x por minuto |

## De onde vem cada dado

| Dado | Fonte |
|---|---|
| Tokens (entrada, saída, cache) | `usage` do evento `turn.complete`, somado a cada turno (inclui subagentes). Só aparece depois do 1º turno. |
| Contexto % e custo US$ | `$.session.usage()`. Se o motor não informar, o widget mostra "sem dados" e **não inventa número**. |
| Limites de uso (5 h, 7 dias, gasto) | `$.session.usage().rateLimits` vira `limits [{kind, pct, resetsAt}]` (`five_hour`, `seven_day`, `spend_limit`). Sem a leitura, a linha correspondente não aparece. Lidos ao fim de cada turno e 1x por minuto; se o horário de reinício já passou e não veio leitura nova, o widget mostra 0%. |
| Modelo | `model` (ex.: "Fable 5.2") |
| Subagentes ativos | `agents [{type, desc, model}]`; a linha "sub" só aparece quando há algum |
| Duração da sessão e do turno | relógio do mod (`$.clock`) |
| Top 5 ferramentas e últimas ações | contadas pelo próprio mod a partir de `tool.call` |
| Linha de status (plano B) | `$.ui.status()` a cada mudança de estado |

## Instalação (outra sessão ou máquina)

1. Copie esta pasta para dentro da pasta de mods da sessão, ou use `--plugin-dir`:
   ```
   claude --plugin-dir C:\caminho\para\claudinho-panel
   ```
2. Nenhum caminho precisa ser ajustado: o mod grava o estado em `<pasta do mod>/claudinho-state.json` (via `$.plugin.root`) e o
   `widget/iniciar-widget.cmd` passa esse arquivo ao widget (`-StateFile`). Para rodar o widget à mão, o padrão do `.ps1` é o mesmo arquivo.
   O widget também guarda a posição vertical (`top`) e o modo reduzido (`compact`) em `%USERPROFILE%\.claude\claudinho-widget.json`.
3. Valide: `claude plugin validate <pasta>` (deve passar sem erros de tipo).
4. Dentro do Claude Code, rode `/claudinho on`.

## Uso

| Comando | O que faz |
|---|---|
| `/claudinho on` | abre o widget na borda direita (fecha um anterior, para não duplicar) |
| `/claudinho off` | fecha o widget (também dá para fechar pelo menu do botão direito) |
| `/claudinho lista` | lista os mascotes |
| `/claudinho mascote azul` | troca a paleta (`coral`, `azul`, `verde`) |

**Widget (notch):** faixa preta de ~72 px colada na borda direita do monitor principal, com cantos esquerdos arredondados e alargamento côncavo em cima e embaixo. De cima para baixo:

| Item | O que mostra |
|---|---|
| Mascote | anel de estado (arco girando em pensando/codando/lendo; âmbar pulsando em aguardando em alerta; verde em terminou; vermelho em erro; cinza nos demais) e o nome curto do estado. Único adereço: o notebook no Codando; o resto o anel já comunica |
| 5h / 7d | linha com rótulo, % e barra fina dos limites `five_hour` e `seven_day` (barra verde até 65%, âmbar até 85%, vermelha acima; o número só ganha cor acima de 65%); só aparece se houver a leitura |
| ctx | linha do contexto (`ctxPct`), "—" sem dado |
| sub | linha com o número de subagentes ativos e uma barra em movimento; só aparece quando há algum |

- **Balão por item:** passe o mouse num item e abre à esquerda um balão preto com seta apontando para ele. Mascote: estado, projeto, o que faz/pede, modelo, sessão/turno e atividade recente. 5h e 7d: janelas de uso com barra e "reinicia em…". ctx: barra, tokens, entrada/saída/custo, cache e ferramentas. sub: descrição e modelo de cada subagente. Ao sair da janela, o balão fecha após ~400 ms; o balão acompanha o conteúdo e nunca sai da tela.
- **Modo reduzido:** clique no mascote (ou "Expandir / reduzir" no menu) para deixar só a bolinha do mascote, sem o nome do estado e sem as linhas de uso (~110 px de altura). A cor do anel continua dizendo o estado, o balão do mascote ganha o resumo `5h · 7d · ctx · sub`, e um **ponto no anel** avisa quando o maior entre 5 h, 7 dias e contexto chega a 75% (âmbar) ou passa de 85% (vermelho). A escolha fica salva.
- **Arraste** na vertical (mais de 3 px) para mudar a posição. **Botão direito:** "Expandir / reduzir", "Fixar balão aberto / soltar" e "Fechar".
- Em **Aguardando você** (alerta) o balão do mascote abre sozinho e fica enquanto durar o alerta; depois fecha em ~10 s sem mouse, a menos que esteja fixado.
- Sem estado ainda (arquivo ausente), a faixa mostra só o mascote parado e o balão diz "Aguardando o Claude Code…".

Não há botão X na superfície: para fechar use o menu do botão direito ou `/claudinho off`.
A redução de movimento segue a configuração de animações do Windows, além de `CW_REDUCE_MOTION=1` (sem pulso, giros e pulos; a altura da faixa muda direto).
Para abrir com o Windows, coloque um atalho de `widget/iniciar-widget.cmd` em `shell:startup`.
Para rodar sem o Claude: `powershell -STA -File widget\claudinho-widget.ps1 -StateFile <json>`.
Depuração: `CW_PIN=mascot|limits|ctx|sub` inicia com o balão daquele item fixado (útil para capturas de tela); `CW_TOP=<px>` força a posição vertical; `CW_COMPACT=0|1` força expandido/reduzido.

**Criar outro mascote:** em `hooks/mascots.ts` copie uma entrada de `MASCOTS` e mude a paleta. Para mudar o desenho, edite `Draw-Mascot` em `widget/claudinho-widget.ps1` (o corpo é montado com retângulos em "unidades de pixel", função `U`).

## Animações por estado

| Estado | Mascote |
|---|---|
| 😴 Ocioso | parado, respirando, olhos fechados |
| 🧠 Pensando | passeia devagar olhando para cima, arco girando no anel |
| 💻 Codando | vira, agacha na frente do notebook (tela piscando) e trota no lugar, arco girando no anel |
| 🔍 Lendo | passeia devagar, arco girando no anel |
| 💬 Sua vez | acena por ~3 s e fica parado, sem alerta (cor neutra); o widget passa a redesenhar ~4x/s |
| 🟡 Aguardando você | pula com os braços para cima e o anel âmbar pulsa (~3 ciclos, depois fixo) |
| ✅ Terminou | pulinho, anel verde |
| ❌ Erro | treme com olhos em X, anel vermelho |

Campos do JSON por estado: `name` (nome completo, título do balão), `short` (nome curto sob o mascote, cabe em ~64 px) e `labelShort` (label curto: alvo da ferramenta, como `claudinho-state.json`, ou o próprio label).

| Estado | `name` | `short` | cor |
|---|---|---|---|
| Ocioso | Ocioso | Ocioso | `#7d7a76` |
| Pensando | Pensando | Pensando | `#6cc4e8` |
| Codando | Codando | Codando | `#d97757` |
| Lendo | Lendo/pesquisando | Lendo | `#a78bfa` |
| Sua vez (`waiting`, `loud=false`) | Sua vez | Sua vez | `#faf9f5` |
| Aguardando você (`waiting`, `loud=true`) | Aguardando você | Responda | `#f5c542` |
| Terminou | Terminou | Terminou | `#5fd38d` |
| Erro | Erro | Erro | `#ff5f56` |

## Limitações conhecidas

- Depois de você aprovar uma permissão, o estado 🟡 só muda no próximo hook (`PostToolUse`); não há evento "permissão concedida". Em um comando longo pode demorar.
- O widget é só para **Windows** (PowerShell 5.1 + WinForms) e só no monitor principal.
- Um mod não consegue desenhar fora do Claude Code; por isso o widget é um processo separado que lê o JSON.
- O painel lateral do terminal (`$.ui.open`) foi **removido de propósito**: ocupava espaço e fazia o chat piscar. O mod não registra mais hook `ui.render`.

## Armadilhas que já encontramos (para quem for mexer)

- **Variável `h` no JSX**: o JSX do mod usa `h` como fábrica. Nunca nomeie um parâmetro `h` (ex.: `.map(h => ...)`), senão dá `h is not a function`.
- **Validador estático**: `$` só pode ser passado para funções declaradas no topo do arquivo (`function f($, ...)`), não para closures dentro de `register`.
- **PowerShell 5.1 lê `.ps1` sem BOM como ANSI**: salve `claudinho-widget.ps1` em UTF-8 **com BOM**, senão os acentos quebram.
- **Fontes em pixels**: o widget é DPI-aware e usa `ScaleTransform`; as fontes são criadas em `GraphicsUnit.Pixel` (função `F`), senão o texto sai 2,25× maior.
- **Argumentos negativos** em chamadas estilo comando do PowerShell precisam de parênteses: `U $B 0 (-31) 35 23`.
- **Brush com alpha**: `Br` multiplica o alpha pela variável global `$script:A` (fade); mantenha a conta `alpha * A / 255`.
- Para tirar prints do widget via PowerShell, chame `SetProcessDPIAware()` antes, senão a captura vem cortada na escala errada.
- **Region**: a janela é só a faixa quando o balão está fechado; com o balão aberto cresce para a esquerda e a `Region` é a união das duas formas (o vão da seta fica de fora). Ela só é recriada quando a geometria muda; a antiga é descartada.
- **Variáveis do PowerShell não diferenciam maiúsculas**: `$trk` e `$TRK` são a mesma. Dentro do `Paint` não reuse nomes de variáveis da paleta global.

## Ideias para continuar

- Detectar "permissão concedida" para sair do 🟡 na hora.
- Iniciar o widget automaticamente no `session.start` (hoje é manual, via `/claudinho on`).
- Notificação sonora (`$.audio.play`) quando entrar em 🟡 em alerta.

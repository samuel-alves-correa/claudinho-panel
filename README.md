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
│  ├─ format.ts                 funções puras de texto (alvo da ferramenta, modelo, tradução, cortes)
│  └─ mascots.ts                paletas dos mascotes (coral, azul, verde)
├─ types/index.d.ts             contrato do estado ($.state) do mod
└─ widget/
   ├─ claudinho-widget.ps1      widget "sempre no topo" (PowerShell + WinForms/GDI+)
   ├─ cenas.ps1                 vinhetas (inseto, quadro, plugue, pendurado, cenas por estado) por cima das animações; ver docs/cenas.md
   └─ iniciar-widget.cmd        abre o widget sem janela de console
(em %USERPROFILE%\.claude\claudinho\state\<sessionId>.json: estado de cada sessão, gerado fora do repositório)
```

Fluxo: **hooks do Claude Code → `register.tsx` atualiza o estado e grava `%USERPROFILE%\.claude\claudinho\state\<sessionId>.json` → `claudinho-widget.ps1` lê a pasta e anima o mascote e as linhas de uso.**
O widget só relê um arquivo quando ele muda; toda a animação (30 fps, 60 fps ao mudar a altura da faixa) é calculada por tempo dentro do widget.

**Várias sessões e sessão encerrada:** cada sessão do Claude Code grava o próprio arquivo e o republica a cada 5 s (o campo `ts` é o heartbeat). O widget considera morta a sessão com `offline: true` (gravado no `session.end`) ou com `ts` há mais de 20 s, e apaga o arquivo depois de 1 h. Entre as vivas, mostra a mais urgente: aguardando em alerta > erro > pensando/codando/lendo > terminou > sua vez > ocioso (empate: `ts` mais recente). Com mais de uma viva, o balão do mascote ganha a lista **SESSÕES** (bolinha na cor do estado, projeto e estado curto; duas sessões do mesmo projeto ganham os 4 primeiros caracteres do id). **Clicar numa sessão fixa a exibição nela** (a bolinha ganha um anel); clicar de novo, ou "Seguir a sessão mais urgente" no menu, solta. Um pedido de permissão ou pergunta de outra sessão passa na frente da fixada ("ALERTA NA FRENTE") até ser respondido; se a fixada encerrar, o widget volta a seguir a mais urgente. A escolha não é salva. Sem nenhuma sessão viva, o mascote fica parado de olhos fechados com "Fechado" e o balão diz "Claude Code fechado".

## Qual hook alimenta qual estado

| Hook | Efeito |
|---|---|
| `prompt.submit` | 🧠 **Pensando** (zera o relógio do turno) |
| `tool.call` (Edit, Write, Bash, PowerShell, outros) | 💻 **Codando** e conta a ferramenta (top 5, histórico) |
| qualquer evento de **subagente** (`agentId` / `agent_id`) | não troca o estado do mascote: a ferramenta só é contada e entra no histórico com `↳`. Exceção: pedido de permissão de subagente ainda vira 🟡, e a ferramenta seguinte dele devolve o estado da conversa principal |
| subagente ativo (`$.agent.list`, status pending/running/waiting) | 🤖 **Agentes** (exibido, não guardado): só no lugar de Sua vez e Ocioso (não troca Pensando/Codando/Lendo, alertas nem Erro; Terminou aparece 4 s antes). Cor rosa dos subagentes, sem alerta; o timer de Ocioso (2 min) não dispara; ao acabar o último volta a 💬 Sua vez |
| `tool.call` (Read, Grep, Glob, LS, WebSearch, WebFetch) | 🔍 **Lendo/pesquisando** (cor própria, roxa) |
| `tool.call` (AskUserQuestion, ExitPlanMode) | 🟡 **Aguardando você** (em alerta) |
| `classic.PermissionRequest` | 🟡 **Aguardando você** (em alerta: precisa de permissão) |
| `classic.Notification` | 🟡 **Aguardando você** (em alerta, exceto `idle_prompt`) |
| `tool.run` | ferramenta liberada para rodar: se estava em 🟡 por permissão/aviso, volta na hora a Codando/Lendo (não vale para AskUserQuestion/ExitPlanMode); também libera o alerta de subagente |
| `classic.PostToolUse` | volta a 🧠 Pensando; mantém Codando/Lendo visível por pelo menos 1,5 s |
| `classic.PostToolUseFailure` | só entra no histórico (`falhou: <ferramenta>`); o estado volta a 🧠 Pensando como no `PostToolUse` |
| `classic.Stop` | ✅ **Terminou** por 4 s, depois 💬 **Sua vez**; grava `doneAt`, e o widget mantém o anel verde e "terminou há X" até você passar o mouse ou mandar outro prompt |
| `turn.complete` | acumula tokens, lê contexto % e custo; se o turno acabou com erro, ❌ **Erro** por 4 s e depois 💬 Sua vez |
| `session.start` | abre o widget automaticamente (sem fechar um já aberto); desliga com `/claudinho auto off` ou `CW_AUTOSTART=0` |
| `session.end` | grava `offline: true` no arquivo da sessão |
| timer de 1 s | 2 min sem atividade viram 😴 **Ocioso**; fim do flash de ✅/❌; relê os limites de uso 1x por minuto; heartbeat a cada 5 s |

## De onde vem cada dado

| Dado | Fonte |
|---|---|
| Tokens (entrada, saída, cache) | `usage` do evento `turn.complete`, somado a cada turno (inclui subagentes). Só aparece depois do 1º turno. |
| Contexto % e custo US$ | `$.session.usage()`. Se o motor não informar, o widget mostra "sem dados" e **não inventa número**. |
| Limites de uso (5 h, 7 dias, gasto) | `$.session.usage().rateLimits` vira `limits [{kind, pct, resetsAt}]` (`five_hour`, `seven_day`, `spend_limit`). Sem a leitura, a linha correspondente não aparece. Lidos ao fim de cada turno e 1x por minuto; se o horário de reinício já passou e não veio leitura nova, o widget mostra "—" (não inventa 0%). |
| Modelo | `model` (ex.: "Fable 5.2") |
| Subagentes ativos | `agents [{type, desc, model}]`; a linha "sub" só aparece quando há algum |
| Duração da sessão e do turno | relógio do mod (`$.clock`) |
| Top 5 ferramentas e últimas ações | contadas pelo próprio mod a partir de `tool.call` |
| Linha de status (plano B) | `$.ui.status()` a cada mudança de estado |

## Instalação (outra sessão ou máquina)

Pelo marketplace (o próprio repositório é um marketplace):
```
/plugin install claudinho-panel --marketplace samuel-alves-correa/claudinho-panel
```

Ou manualmente:

1. Copie esta pasta para dentro da pasta de mods da sessão, ou use `--plugin-dir`:
   ```
   claude --plugin-dir C:\caminho\para\claudinho-panel
   ```
2. Nenhum caminho precisa ser ajustado: o mod grava o estado em `%USERPROFILE%\.claude\claudinho\state\<sessionId>.json` e o widget lê essa mesma pasta por padrão (`-StateDir` só serve para testes). A pasta é fixa para não mudar quando o plugin é atualizado de versão.
   O widget guarda posição vertical (`top`), modo reduzido (`compact`) e redução de movimento (`reduceMotion`) em `%USERPROFILE%\.claude\claudinho-widget.json`, e o próprio PID em `%USERPROFILE%\.claude\claudinho-widget.pid` (é por ele que `/claudinho off` fecha só o widget). **Um widget só:** o script pega o mutex `Local\ClaudinhoWidget` ao abrir; se outro widget já o tem (launcher aberto na mão, dois `/claudinho on` ao mesmo tempo em sessões diferentes), o novo espera até 3 s e sai sem abrir janela nem mexer no `.pid`. `CW_NO_PID=1` pula a trava (testes com outro widget aberto).
3. Valide: `claude plugin validate <pasta>` (deve passar sem erros de tipo).
4. O widget abre sozinho no início da sessão; se estiver desligado, rode `/claudinho on`.

## Uso

| Comando | O que faz |
|---|---|
| `/claudinho on` | abre o widget na borda direita (fecha um anterior, para não duplicar) |
| `/claudinho off` | fecha o widget (também dá para fechar pelo menu do botão direito) |
| `/claudinho lista` | lista os mascotes |
| `/claudinho mascote azul` | troca a paleta (`coral`, `azul`, `verde`) |
| `/claudinho auto on\|off` | liga/desliga abrir o widget no início da sessão (salvo; `CW_AUTOSTART=0` também desliga) |
| `/claudinho som on\|off` | liga/desliga o som do sistema ao entrar em 🟡 em alerta (salvo; só Windows) |

**Widget (notch):** faixa preta de ~72 px colada na borda direita do monitor principal, com cantos esquerdos arredondados e alargamento côncavo em cima e embaixo. De cima para baixo:

| Item | O que mostra |
|---|---|
| Mascote | anel de estado (arco girando em pensando/codando/lendo; âmbar pulsando em aguardando em alerta; verde em terminou; vermelho em erro; cinza nos demais) e o nome curto do estado (em serifa, Georgia), com uma linha de contexto embaixo: ferramenta e relógio do turno no Codando/Lendo ("Bash  1:23"), relógio no Pensando, "há 42 s" em âmbar aguardando você, número de subagentes no Agentes e "há 12 min" desde o fim do turno. Único adereço: o notebook no Codando; o resto o anel já comunica |
| 5h / 7d | anel que enche no sentido horário com o rótulo dentro (argila abaixo de 75%, âmbar de 75 a 89%, vermelho a partir de 90%), o % ao lado e um detalhe embaixo: o horário em que zera (5h: "15:40"; 7d: "sex 13h"). Projeção pelo ritmo médio da janela (depois de 10% dela): se o uso chega a 100% antes de zerar, o % e o detalhe ficam âmbar com o fim previsto ("→ qui" ou "→ 14:20"); se não, um tracinho cinza no anel marca onde o uso termina a janela. Só aparece se houver a leitura |
| ctx | anel do contexto (`ctxPct`) com os tokens em uso embaixo ("36k"), "—" sem dado |
| sub | linha com o número de subagentes ativos e uma barra em movimento, em rosa (`#f472b6`); só aparece quando há algum |
| rodapé | projeto, modelo e custo da sessão, discretos; passar o mouse abre o balão do mascote |

- **Balão por item:** passe o mouse num item (abre após ~180 ms) e aparece à esquerda um balão grafite com seta apontando para ele. **Clique num item fixa o balão dele; outro clique solta.** O pino não é salvo (some ao reiniciar) e, com o Claude Code fechado, o balão só abre ao passar o mouse; clicar no próprio balão aberto ou em qualquer lugar fora do widget fecha. Se o item fixado não existir no momento, aparece o balão do mascote. Mascote: estado, projeto, o que faz/pede, modelo, sessão/turno e atividade recente. 5h e 7d: janelas de uso com barra e "reinicia em…". ctx: barra, tokens, entrada/saída/custo, cache e ferramentas. sub: descrição e modelo de cada subagente. Ao sair da janela, o balão fecha após ~400 ms; o balão acompanha o conteúdo e nunca sai da tela.
- **Modo reduzido:** duplo clique no mascote (ou "Reduzir" / "Expandir" no menu) para deixar só a bolinha do mascote, sem o nome do estado e sem as linhas de uso (~110 px de altura). A cor do anel continua dizendo o estado, o balão do mascote ganha o resumo `5h · 7d · ctx · sub`, e um **selo com "!"** no anel avisa quando o maior entre 5 h, 7 dias e contexto chega a 75% (âmbar) ou a 90% (vermelho). A escolha fica salva.
- **Arraste** na vertical (mais de 3 px) para mudar a posição. **Botão direito:** "Reduzir" ou "Expandir", "Fixar balão" ou "Soltar balão", "Reduzir movimento" (marcável), "Monitor" (submenu com as telas; só aparece com 2 ou mais) e "Fechar".
- **Atalho global Ctrl+Alt+C:** fixa/solta o balão do mascote sem roubar o foco. `CW_HOTKEY=0` desliga; `CW_HOTKEY=ctrl+shift+k` troca (um modificador e uma letra). Se a combinação já estiver em uso por outro programa, o widget segue sem atalho.
- **Monitor:** a escolha fica salva no campo `monitor` do config (DeviceName, ex.: `\\.\DISPLAY2`); se a tela sumir, volta ao principal. A posição vertical é só limitada à área da nova tela.
- Em **Aguardando você** (alerta) o balão do mascote abre sozinho, com o pedido em até 3 linhas. Um clique no widget dispensa o balão; ele só reabre num alerta novo.
- Sem estado ainda (pasta vazia), a faixa mostra só o mascote parado e o balão diz "Aguardando o Claude Code…".
- A janela não rouba o foco do terminal nem aparece no Alt+Tab, e se esconde enquanto houver uma janela em tela cheia no monitor principal. Área de trabalho e DPI são reconsultados a cada 2 s.
- Durações usam um só formato: "45 s", "12 min", "1 h 05". Custo aparece como "US$ 1,23".

Não há botão X na superfície: para fechar use o menu do botão direito ou `/claudinho off`.
A redução de movimento segue a configuração de animações do Windows, o item "Reduzir movimento" do menu e `CW_REDUCE_MOTION=1` (sem pulso, giros e pulos; a altura da faixa muda direto).
Para abrir com o Windows, coloque um atalho de `widget/iniciar-widget.cmd` em `shell:startup`.
Para rodar sem o Claude: `powershell -STA -File widget\claudinho-widget.ps1 -StateDir <pasta>`.
Depuração: `CW_MONITOR=<DeviceName>` força o monitor (precede o config); `CW_PIN=mascot|limits|ctx|sub` inicia com o balão daquele item fixado (útil para capturas de tela); `CW_TOP=<px>` força a posição vertical; `CW_COMPACT=0|1` força expandido/reduzido; `CW_NO_PID=1` não grava nem apaga o `.pid` e `CW_CFG=<arquivo>` usa outra config (para testar com outro widget aberto).

**Criar outro mascote:** em `hooks/mascots.ts` copie uma entrada de `MASCOTS` e mude a paleta. Para mudar o desenho, edite `Draw-Mascot` em `widget/claudinho-widget.ps1` (o corpo é montado com retângulos em "unidades de pixel", função `U`).

## Animações por estado

| Estado | Mascote |
|---|---|
| 😴 Ocioso | parado, respirando, olhos fechados (de vez em quando uma cena do rodízio, como a `borboleta`) |
| 🧠 Pensando | passeia devagar olhando para cima, arco girando no anel; depois de 1,5 s, cena `lampada` (lâmpada fraca piscando sobre a cabeça, que acende forte quando ele sai do Pensando) |
| 💻 Codando | vira, agacha na frente do notebook (tela piscando) e trota no lugar, arco girando no anel; com `Bash`, cena `terminal` (linhas verdes subindo e um `$` novo ao terminar); com `Edit`, cena `costura` (troca um pedaço da faixa de código e costura com agulha e linha) |
| 🔍 Lendo | passeia devagar, arco girando no anel; com `Read`/`Glob`/`LS`, cena `lupa` (anda com a lupa seguindo pegadas no chão) |
| 💬 Sua vez | acena por ~3 s e fica parado, sem alerta (cor neutra); o widget passa a redesenhar ~4x/s |
| 🤖 Agentes | subagente rodando com a conversa principal em Sua vez ou Ocioso (o ✅ Terminou ainda aparece por 4 s antes): cena `chefe` (prancheta e mini-Claudinhos carregando caixas) ou `pescaria` (uma linha por subagente; cada um que termina vira um peixe), alternando, e depois de 25 s, `cochilo` (cochila com um olho aberto e acorda num pulo quando um subagente termina) |
| 🟡 Aguardando você | pula com os braços para cima e o anel âmbar pulsa (~3 ciclos, depois fixo); na permissão, cena `placa` (levanta uma placa "OK?" e balança); em pergunta/plano, cena `quadro` |
| ✅ Terminou | pulinho, anel verde (o verde fica até você passar o mouse); cena `plugue` ou `bandeira` (finca uma bandeirinha verde), alternando |
| ❌ Erro | treme com olhos em X, anel vermelho (só quando o turno termina com erro); depois, cena `fumaca` (o notebook solta fumaça e ele abana) |
| Fechado | parado, olhos fechados, sem animação (nenhuma sessão viva) |

**Cenas** (`widget/cenas.ps1`, detalhes em `docs/cenas.md`): subagente ativo → chefe de obra ou pescaria (um mini-Claudinho ou uma linha por subagente) e, depois de 25 s, cochilo vigiado; ferramenta falhou → uma joaninha entra e leva um tapa; pergunta ou plano esperando você → quadro com "?" ao lado; turno terminou → plugue encaixa ou bandeira fincada (alternando); arrastar o widget → fica pendurado e quica ao soltar; parado em Ocioso/Sua vez → uma de plugue, inseto, quadro ou borboleta a cada 40–80 s. Cenas do estado (em laço enquanto o estado durar; qualquer outra cena passa por cima): terminal (Bash), costura (Edit), lâmpada (Pensando), lupa (Read/Glob/LS), fumaça (Erro), placa (permissão). `CW_CENAS=0` desliga; `CW_CENA=<nome>` repete uma em laço.

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

- Em pergunta (`AskUserQuestion`) ou plano (`ExitPlanMode`), o 🟡 só sai no `PostToolUse`, porque a ferramenta roda enquanto espera a resposta. Permissões saem na hora via `tool.run`.
- O som de alerta usa o som do sistema do Windows (`$.audio.play` só toca no macOS); em outros sistemas fica mudo.
- O widget é só para **Windows** (PowerShell 5.1 + WinForms) e fica sempre na borda direita (a esquerda exigiria espelhar balão, setas e hit-tests).
- DPI por monitor exige Windows 10 1703+ (antes disso, usa o DPI do sistema); uma troca de escala aparece em até 2 s.
- Um mod não consegue desenhar fora do Claude Code; por isso o widget é um processo separado que lê o JSON.
- Sem leitor de tela; pelo teclado só o atalho do balão.
- Depois de um `/clear` o mod marca o id antigo como offline e publica o novo id no tick seguinte (até 1 s); o fluxo foi revisado no código, mas ainda não exercitado em uso real.
- O painel lateral do terminal (`$.ui.open`) foi **removido de propósito**: ocupava espaço e fazia o chat piscar. O mod não registra mais hook `ui.render`.

## Armadilhas que já encontramos (para quem for mexer)

- **Variável `h` no JSX**: o JSX do mod usa `h` como fábrica. Nunca nomeie um parâmetro `h` (ex.: `.map(h => ...)`), senão dá `h is not a function`.
- **Mudou o `St`?** Troque a tag `shape` do atom em `register.tsx` (hoje `st-7`), senão o estado guardado pela versão antiga volta.
- **Sem API para apagar arquivo no mod**: sessão encerrada vira `offline: true` e quem apaga o arquivo é o widget.
- **Janela que nunca fica ativa** (`Cw.NForm`, `WS_EX_NOACTIVATE`): o menu de contexto não fecha sozinho ao clicar fora, então há um fechamento manual por clique fora do widget (o mesmo vale para o balão fixado: o clique em outra janela é detectado com `GetAsyncKeyState`).
- **Validador estático**: `$` só pode ser passado para funções declaradas no topo do arquivo (`function f($, ...)`), não para closures dentro de `register`.
- **PowerShell 5.1 lê `.ps1` sem BOM como ANSI**: salve `claudinho-widget.ps1` em UTF-8 **com BOM**, senão os acentos quebram.
- **Fontes em pixels**: o widget é DPI-aware e usa `ScaleTransform`; as fontes são criadas em `GraphicsUnit.Pixel` (função `F`), senão o texto sai 2,25× maior.
- **Argumentos negativos** em chamadas estilo comando do PowerShell precisam de parênteses: `U $B 0 (-31) 35 23`.
- Para tirar prints do widget via PowerShell, chame `SetProcessDPIAware()` antes, senão a captura vem cortada na escala errada.
- **Region**: a janela é só a faixa quando o balão está fechado; com o balão aberto cresce para a esquerda e a `Region` é a união das duas formas (o vão da seta fica de fora). Ela só é recriada quando a geometria muda; a antiga é descartada.
- **Variáveis do PowerShell não diferenciam maiúsculas**: `$trk` e `$TRK` são a mesma. Dentro do `Paint` não reuse nomes de variáveis da paleta global.
- **Timer de quadros (`Cw.Pulse`)**: o `Timer` do WinForms arredonda para o tick do sistema (~15,6 ms), então 33 ms viravam ~47 ms (21 fps); `timeBeginPeriod` não muda isso. A `Pulse` conta o tempo numa thread própria (com `timeBeginPeriod(1)`) e dispara `Tick` na thread da janela via `BeginInvoke`, um por vez.
- **Camada fixa em bitmap**: o custo do `Paint` é o interpretador do PowerShell, não o GDI+. Fundo, nome, linhas de uso e balão são desenhados num bitmap (em pixels do dispositivo, opaco para o ClearType sair igual) só quando a forma, o estado ou o item aberto mudam, ou a cada segundo nos balões com tempos; cada quadro copia o bitmap e desenha só anel, mascote, selo e a barra de subagentes. Algo novo que dependa do tempo precisa entrar na chave (`$lk`) ou no trecho animado do `Paint`.

## Ideias para continuar

- Escolher a borda (esquerda/direita); tratar `WM_DPICHANGED` para a escala mudar na hora.
- LICENSE e ícone, se for submeter ao diretório de plugins (o validador avisa).

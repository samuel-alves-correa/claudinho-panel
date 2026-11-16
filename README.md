# Claudinho: mod do Claude Code com mascote e status do agente

Mod para o Claude Code que mostra, em tempo real, **o que o agente está fazendo** e **o uso da sessão**.
O mascote em pixel art (um bichinho laranja visto de lado, no estilo do app do Claude) muda de animação conforme o estado.
Ele aparece num **widget fixo na borda direita da tela** (sempre no topo, recolhível) e também numa **linha de status** dentro do Claude Code.

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

Fluxo: **hooks do Claude Code → `register.tsx` atualiza o estado e grava `claudinho-state.json` na pasta do mod → `claudinho-widget.ps1` lê o JSON e anima o mascote.**
O widget só relê o arquivo quando ele muda; toda a animação (30 fps, 60 fps ao expandir) é calculada por tempo dentro do widget.

## Qual hook alimenta qual estado

| Hook | Efeito |
|---|---|
| `prompt.submit` | 🧠 **Pensando** (zera o relógio do turno) |
| `tool.call` (Edit, Write, Bash, PowerShell, outros) | 💻 **Codando** e conta a ferramenta (top 5, histórico) |
| `tool.call` (Read, Grep, Glob, LS, WebSearch, WebFetch) | 🔍 **Lendo/pesquisando** |
| `tool.call` (AskUserQuestion, ExitPlanMode) | 🟡 **Aguardando você** (em alerta) |
| `classic.PermissionRequest` | 🟡 **Aguardando você** (em alerta: precisa de permissão) |
| `classic.Notification` | 🟡 **Aguardando você** (em alerta, exceto `idle_prompt`) |
| `classic.PostToolUse` | volta a 🧠 Pensando; mantém Codando/Lendo visível por pelo menos 1,5 s |
| `classic.PostToolUseFailure` | ❌ **Erro** por 4 s |
| `classic.Stop` | ✅ **Terminou** por 4 s, depois 🟡 "sua vez" (sem alerta) |
| `turn.complete` | acumula tokens, lê contexto % e custo |
| timer de 1 s | 2 min sem atividade viram 😴 **Ocioso**; fim do flash de ✅/❌ |

## De onde vem cada dado

| Dado | Fonte |
|---|---|
| Tokens (entrada, saída, cache) | `usage` do evento `turn.complete`, somado a cada turno (inclui subagentes). Só aparece depois do 1º turno. |
| Contexto % e custo US$ | `$.session.usage()`. Se o motor não informar, o widget mostra `n/d` e **não inventa número**. |
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
   O widget também guarda posição e se estava expandido em `%USERPROFILE%\.claude\claudinho-widget.json`.
3. Valide: `claude plugin validate <pasta>` (deve passar sem erros de tipo).
4. Dentro do Claude Code, rode `/claudinho on`.

## Uso

| Comando | O que faz |
|---|---|
| `/claudinho on` | abre o widget na borda direita (fecha um anterior, para não duplicar) |
| `/claudinho off` | fecha o widget |
| `/claudinho lista` | lista os mascotes |
| `/claudinho mascote azul` | troca a paleta (`coral`, `azul`, `verde`) |

**Widget:** clique recolhe/expande; arraste para cima/baixo para mudar a altura; botão direito abre o menu (Expandir/recolher, Fechar). Ele começa recolhido.
Para abrir com o Windows, coloque um atalho de `widget/iniciar-widget.cmd` em `shell:startup`.
Para rodar sem o Claude: `powershell -STA -File widget\claudinho-widget.ps1` (use `$env:CW_EXPAND=1` para já iniciar expandido).

**Criar outro mascote:** em `hooks/mascots.ts` copie uma entrada de `MASCOTS` e mude a paleta. Para mudar o desenho, edite `Draw-Mascot` em `widget/claudinho-widget.ps1` (o corpo é montado com retângulos em "unidades de pixel", função `U`).

## Animações por estado

| Estado | Mascote |
|---|---|
| 😴 Ocioso | parado, respirando, olhos fechados, "z" subindo |
| 🧠 Pensando | passeia devagar olhando para cima, bolinhas pulsando |
| 💻 Codando | trota no lugar sobre um teclado, símbolos `{ } ; =>` subindo |
| 🔍 Lendo | passeia com uma lupa na ponta da vareta |
| 🟡 Aguardando você | pula, vareta balança, balão amarelo "!" e borda/brilho pulsando |
| ✅ Terminou | pulinho com brilhos |
| ❌ Erro | treme com olhos em X |

O asterisco giratório `· ✢ ✳ ✶ ✻ ✽` (igual ao spinner do terminal) fica ao lado do nome do estado enquanto o agente trabalha.

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

## Ideias para continuar

- Detectar "permissão concedida" para sair do 🟡 na hora.
- Iniciar o widget automaticamente no `session.start` (hoje é manual, via `/claudinho on`).
- Lembrar posição e se estava expandido entre execuções.
- Notificação sonora (`$.audio.play`) quando entrar em 🟡 em alerta.

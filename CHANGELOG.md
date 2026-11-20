# Changelog

Versões do Claudinho (`.claude-plugin/plugin.json`). Cada versão tem uma tag `vX.Y.Z` no commit em que foi declarada.

## Não lançado

### Correções
- O widget congelava no último estado desenhado (por exemplo, Codando enquanto a sessão estava em Sua vez): o atalho global sobrescrevia a cultura pt-BR e toda formatação de número falhava a cada quadro.
- A cultura pt-BR do widget agora é constante: um código que tente sobrescrevê-la falha só naquele ponto, sem travar o desenho.

### Documentação
- GIFs do mascote no README.

## 0.4.0 — 2026-11-17

### Novidades
- Cenas por estado: terminal e costura no Codando, lâmpada no Pensando, lupa no Lendo, fumaça no Erro, bandeira no Terminou, placa na permissão, borboleta no rodízio do Ocioso.
- Cenas no estado Agentes: chefe de obra, cochilo vigiado (com minis correndo em volta) e pescaria.
- O mod publica a ferramenta em uso, para as cenas do Codando e do Lendo.
- Lista de sessões no balão do mascote e trava para existir um widget só.
- Faixa expandida com anéis de uso, linha de contexto, projeção e rodapé.
- Widget abre sozinho, som de alerta, atalho global, DPI por monitor e escolha de monitor.

### Correções
- A cena aguardando toca a saída quando o subagente acaba.
- Mini-agentes maiores e rosa na cena chefe.
- O alerta só sai pela chamada que pediu a permissão, o som toca uma vez por alerta e o publish informa se gravou.

## 0.3.0 — 2026-11-17

### Novidades
- Estado em pasta fixa (`~/.claude/claudinho/state`), timer de quadros preciso e balão fixado sem persistir.
- Cenas inspiradas no app mobile: inseto, quadro, plugue e pendurado.
- Estado Agentes e cena aguardando subagentes.

## 0.2.0 — 2026-11-16

### Novidades
- Widget em notch com várias sessões: modo reduzido, linhas de uso e notebook no Codando.
- Modelo e subagentes no widget, melhorias de design.

## 0.1.0 — 2026-11-16

- Primeira versão: mod com mascote e widget de status do agente.

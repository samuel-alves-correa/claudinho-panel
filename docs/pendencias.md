# Pendências (revisão de 17/11/2026)

Saíram da revisão do commit `b59c7c4` e ainda não foram feitas.

## Widget (`widget/claudinho-widget.ps1`)

- [ ] **`CW_MONITOR` fica gravado na config.** O `Save-Cfg` grava `$script:monitor` mesmo quando ele veio da variável de depuração, e o `top` salvo é descartado. Correção: guardar o monitor da config separado do override e gravar só o da config.
- [ ] **A troca de monitor perde a posição** (`Set-Monitor`). O `top` é um Y absoluto e só é limitado à nova área. Com telas desalinhadas, o widget vai para a borda. Correção: `top = (top - wa0.Top) / H0 * H1 + wa1.Top`, isto é, a mesma altura relativa.
- [ ] **A troca de monitor com escala diferente** não converte o `top` nem outros valores em pixels do DPI antigo para o novo. Entra na mesma correção acima.
- [ ] **`CW_HOTKEY` só aceita letra.** `ctrl+alt+f9` desliga o atalho sem avisar. Aceitar `f1`..`f12`, ou ao menos escrever um aviso.

## Testes que não rodaram (agente testador interrompido)

- [ ] Várias sessões falsas: a mais urgente aparece; fixar e soltar uma sessão.
- [ ] Captura de cada estado e de cada cena (`CW_CENA`).
- [ ] O atalho abre e fecha o balão de verdade (usar `CW_HOTKEY=ctrl+alt+k` se o widget real já tiver o Ctrl+Alt+C).
- [ ] Modo reduzido, balão fixado (`CW_PIN`), e "um widget só" com dois lançamentos seguidos.
- [ ] Arquivo de estado vazio, corrompido ou apagado não derruba o widget.

Cuidado: com o widget real aberto, testar com `CW_NO_PID=1`, `CW_CFG=<temp>` e `-StateDir <temp>`, sem fechar o widget real.

## Mod (`hooks/register.tsx`)

- [ ] Exercitar em uso real: permissão com ferramentas em paralelo (o 🟡 só sai quando roda a ferramenta que pediu), o som tocando uma vez só, e o `/clear`.
- [ ] Uma permissão que só chega pelo `Notification`, sem `PermissionRequest`, não sai pelo `tool.run`. Ela sai no `PostToolUse`, como antes. Conferir se esse caso existe.

## Fechamento

- [ ] Abrir o PR de `feat/cenas` para a `main` (o `gh` não está instalado nesta máquina).

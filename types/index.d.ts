export type Mode = 'thinking' | 'coding' | 'reading' | 'waiting' | 'idle' | 'done' | 'error' | 'agents'

export type St = {
  mode: Mode
  /** waiting que precisa de você agora (permissão/pergunta), não só "sua vez" */
  loud: boolean
  label: string
  since: number
  sessionStart: number
  turnStart: number
  flashUntil: number
  inTok: number
  outTok: number
  cacheTok: number
  hasUsage: boolean
  ctxPct: number | null
  usd: number | null
  counts: Record<string, number>
  history: { t: number; text: string }[]
  /** quando o turno principal terminou (ms epoch); 0 = nada. Zera no próximo prompt */
  doneAt: number
  /** quando entrou em waiting (ms epoch); 0 fora de waiting */
  waitSince: number
  /** resumo do que esta sendo pedido: ferramenta + alvo curto */
  ask: string
  /** tokens usados e janela de contexto (so se session.usage informar) */
  ctxTok: number | null
  ctxWin: number | null
  /** label curto para o widget recolhido (alvo da ferramenta, ou o próprio label) */
  labelShort: string
  /** modelo de cada subagente (id -> modelo), anotado no agent.spawn; guarda os 20 últimos */
  agentModels: Record<string, string>
  /** janelas de limite de uso (five_hour, seven_day, spend_limit); vazio sem leitura */
  limits: { kind: string; pct: number; resetsAt: number }[]
  /** a conversa principal está no meio de um turno (do prompt.submit até o Stop) */
  busy: boolean
  /** última falha de ferramenta da conversa principal (ms epoch); 0 = nenhuma. O widget toca a cena do inseto */
  failAt: number
  /** tipo do pedido em waiting+loud; o widget mostra o quadro em 'pergunta' e 'plano' */
  askKind: AskKind
  /** ferramenta da conversa principal rodando em Codando/Lendo ('' fora deles); o widget escolhe a cena por ela */
  tool: string
}

export type AskKind = '' | 'pergunta' | 'plano' | 'permissao' | 'aviso'

declare module 'claude-code' {
  interface PluginState {
    'claudinho-panel': { st: Shaped<St> }
  }
}

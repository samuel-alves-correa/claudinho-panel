export type Mode = 'thinking' | 'coding' | 'reading' | 'waiting' | 'idle' | 'done' | 'error'

export type St = {
  mode: Mode
  /** waiting que precisa de você agora (permissão/pergunta), não só "sua vez" */
  loud: boolean
  label: string
  since: number
  frame: number
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
}

declare module 'claude-code' {
  interface PluginState {
    'claudinho-panel': { st: Shaped<St> }
  }
}

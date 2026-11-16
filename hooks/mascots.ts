// Cores dos mascotes. O desenho fica no widget (Draw-Mascot em widget/claudinho-widget.ps1).
// Para criar um novo: copie um item de MASCOTS e mude B (corpo) e D (corpo escuro).
export type Mascot = { label: string; palette: { B: string; D: string } }

export const MASCOTS: Record<string, Mascot> = {
  coral: { label: 'Coral (estilo Claude Code)', palette: { B: '#d97757', D: '#a8553a' } },
  azul: { label: 'Azulzinho', palette: { B: '#5b8def', D: '#3b5db0' } },
  verde: { label: 'Verdinho', palette: { B: '#6cc070', D: '#43873f' } },
}

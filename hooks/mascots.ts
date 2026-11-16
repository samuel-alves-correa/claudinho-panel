// Mascotes em pixel art. Cada pixel vira 2 caracteres "██".
// Para criar um novo: copie um item de MASCOTS, mude a paleta ou as linhas do sprite.
// Letras: B corpo  D corpo escuro  E olho  Y amarelo  G verde  R vermelho  C ciano  K tecla  W branco  . vazio
import type { Mode } from '../types'

export type Mascot = { label: string; palette: Record<string, string> }

const BASE = {
  D: '#a8553a', E: '#1c1410', Y: '#f5c542', G: '#5fd38d',
  R: '#ff5f56', C: '#6cc4e8', K: '#555a63', W: '#e8e6e3',
}

export const MASCOTS: Record<string, Mascot> = {
  coral: { label: 'Coral (estilo Claude Code)', palette: { ...BASE, B: '#d97757' } },
  azul: { label: 'Azulzinho', palette: { ...BASE, B: '#5b8def', D: '#3b5db0' } },
  verde: { label: 'Verdinho', palette: { ...BASE, B: '#6cc070', D: '#43873f' } },
}

function deco(mode: Mode, f: number): string {
  const a = f % 2 === 0
  switch (mode) {
    case 'waiting': return a ? 'Y.......Y' : '.Y.....Y.'
    case 'thinking': return ['......C..', '....C.C..', '..C.C.C..'][f % 3] ?? '.........'
    case 'coding': return a ? '.....W...' : '......W..'
    case 'reading': return a ? '.......C.' : '.........'
    case 'idle': return a ? '......W..' : '.......W.'
    case 'done': return a ? 'G.G...G.G' : '.G.....G.'
    case 'error': return a ? 'R.......R' : '.R.....R.'
  }
}

export function sprite(mode: Mode, f: number): string[] {
  const a = f % 2 === 0
  const eyeRow = (e: string) => `.B${e}BBB${e}B.`
  let r1 = '.BBBBBBB.'
  let r2 = eyeRow(a ? 'E' : 'D') // pisca
  let r3 = 'BBBBBBBBB'
  let r4 = '.BBBBBBB.'
  let keys = '.........'
  if (mode === 'thinking') { r1 = eyeRow('E'); r2 = '.BBBBBBB.' } // olha pra cima
  if (mode === 'waiting') { r2 = eyeRow(f % 6 < 4 ? 'E' : 'D') } // olha pra você, pisca de vez em quando
  if (mode === 'idle') { r2 = eyeRow('D'); r3 = '.BBBBBBB.' }
  if (mode === 'done') r2 = eyeRow('D')
  if (mode === 'error') r2 = eyeRow('R')
  if (mode === 'reading') r3 = 'BBBBBBBBC'
  if (mode === 'coding') {
    r3 = '.BBBBBBB.'
    r4 = a ? 'BBBBBBBBB' : '.BBBBBBB.'
    keys = a ? 'KWKWKWKWK' : 'WKWKWKWKW'
  }
  const walk = mode === 'coding' || mode === 'reading'
  const legs = walk && !a ? '.D.D.D.D.' : 'D.D.D.D.D'
  return [deco(mode, f), r1, r2, r3, r4, legs, keys]
}

import { useState } from 'react';
import { Moon, Sun } from 'lucide-react';

function temaAtual(): 'light' | 'dark' {
  const t = document.documentElement.dataset.theme;
  if (t === 'light' || t === 'dark') return t;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function BotaoTema({ comTexto = false }: { comTexto?: boolean }) {
  const [tema, setTema] = useState(temaAtual);
  function trocar() {
    const novo = tema === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = novo;
    try { localStorage.setItem('tema', novo); } catch { /* sem storage */ }
    setTema(novo);
  }
  const Icone = tema === 'dark' ? Sun : Moon;
  return comTexto ? (
    <button className="nav-btn" onClick={trocar}><Icone size={17} /> {tema === 'dark' ? 'Tema claro' : 'Tema escuro'}</button>
  ) : (
    <button className="btn icone" onClick={trocar} title="Alternar tema" aria-label="Alternar tema"><Icone size={17} /></button>
  );
}

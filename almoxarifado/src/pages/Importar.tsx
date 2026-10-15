import { useState } from 'react';
import { FileUp } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useDados } from '../lib/dados';
import { lerPlanilha } from '../lib/importar';
import { contar } from '../lib/util';
import type { ItemNovo } from '../lib/types';

export function Importar() {
  const { itens: atuais, recarregar, aviso } = useDados();
  const [itens, setItens] = useState<ItemNovo[] | null>(null);
  const [nome, setNome] = useState('');
  const [modo, setModo] = useState<'substituir' | 'adicionar'>(atuais.length ? 'adicionar' : 'substituir');
  const [prog, setProg] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  async function escolher(f: File | undefined) {
    if (!f) return;
    setErro(null); setItens(null); setNome(f.name);
    try { setItens(await lerPlanilha(f)); } catch (e) { setErro((e as Error).message); }
  }

  async function importar() {
    if (!itens) return;
    if (modo === 'substituir' && !confirm(`Isto APAGA os ${atuais.length} itens atuais, saídas e histórico do sistema e carrega ${itens.length} itens da planilha. Continuar?`)) return;
    setProg(0);
    try {
      if (modo === 'substituir') {
        const { error } = await supabase.rpc('limpar_inventario');
        if (error) throw error;
      }
      for (let i = 0; i < itens.length; i += 300) {
        const { error } = await supabase.from('itens').insert(itens.slice(i, i + 300));
        if (error) throw error;
        setProg(Math.min(itens.length, i + 300));
      }
      aviso(`${itens.length} itens importados`);
      setItens(null);
      await recarregar();
    } catch (e) {
      setErro((e as Error).message);
    } finally {
      setProg(null);
    }
  }

  const resumo = itens ? contar(itens, (i) => i.tipo) : [];

  return (
    <>
      <div className="topo"><div><h1>Importar planilha</h1>
        <p>Carregue o arquivo "Inventário Almoxarifado Técnico" (.xlsx). A primeira aba é lida pelos nomes das colunas.</p></div></div>

      <div className="card card-pad stack" style={{ maxWidth: 720 }}>
        <label className="btn" style={{ width: 'fit-content' }}>
          <FileUp size={16} /> Escolher arquivo .xlsx
          <input type="file" accept=".xlsx,.xls" hidden onChange={(e) => escolher(e.target.files?.[0])} />
        </label>
        {nome && <div className="muted">{nome}</div>}
        {erro && <div className="aviso bad">{erro}</div>}

        {itens && (
          <>
            <div className="aviso ok">
              <b>{itens.length} itens</b> encontrados: {resumo.map(([t, n]) => `${t} ${n}`).join(' · ')}.
              {' '}{itens.filter((i) => i.ultima_inspecao).length} com data de inspeção, {itens.filter((i) => i.ano_entrada).length} com ano de entrada.
            </div>
            <div className="campo"><span>Como importar</span>
              <div className="chips">
                <button type="button" className={'chip' + (modo === 'substituir' ? ' on' : '')} onClick={() => setModo('substituir')}>Substituir tudo</button>
                <button type="button" className={'chip' + (modo === 'adicionar' ? ' on' : '')} onClick={() => setModo('adicionar')}>Adicionar aos {atuais.length} atuais</button>
              </div>
            </div>
            {modo === 'substituir' && atuais.length > 0 && <div className="aviso warn">Substituir apaga itens, saídas e linha do tempo existentes.</div>}
            <button className="btn prim" style={{ width: 'fit-content' }} disabled={prog != null} onClick={importar}>
              {prog != null ? `Importando… ${prog}/${itens.length}` : `Importar ${itens.length} itens`}
            </button>
          </>
        )}
      </div>
    </>
  );
}

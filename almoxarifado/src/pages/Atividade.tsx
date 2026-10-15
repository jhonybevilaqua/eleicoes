import { useEffect, useMemo, useState } from 'react';
import { Search } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useNav } from '../App';
import type { Evento } from '../lib/types';
import { fmtData, semAcento } from '../lib/util';

const ACOES = ['SAÍDA', 'DEVOLUÇÃO', 'INSPEÇÃO', 'STATUS', 'EDIÇÃO', 'CADASTRO', 'EXCLUSÃO'];

export function Atividade() {
  const { abrirItem } = useNav();
  const [eventos, setEventos] = useState<Evento[] | null>(null);
  const [acao, setAcao] = useState('');
  const [q, setQ] = useState('');

  useEffect(() => {
    setEventos(null);
    let c = supabase.from('eventos').select('*, itens(equipamento, codigo_almox)').order('created_at', { ascending: false }).limit(500);
    if (acao) c = c.eq('acao', acao);
    c.then(({ data }) => setEventos((data as Evento[]) || []));
  }, [acao]);

  const lista = useMemo(() => {
    const t = semAcento(q).split(/\s+/).filter(Boolean);
    return (eventos || []).filter((e) => {
      if (!t.length) return true;
      const s = semAcento([e.acao, e.detalhe, e.usuario, e.itens?.equipamento, e.itens?.codigo_almox].join(' '));
      return t.every((x) => s.includes(x));
    });
  }, [eventos, q]);

  return (
    <>
      <div className="topo"><div><h1>Atividade</h1><p>Registro de tudo que foi feito no sistema (últimos 500 eventos)</p></div></div>
      <div className="card">
        <div className="filtros">
          <div className="busca"><Search size={16} /><input className="inp" placeholder="Buscar…" value={q} onChange={(e) => setQ(e.target.value)} /></div>
          <select className="inp" value={acao} onChange={(e) => setAcao(e.target.value)}>
            <option value="">Todas as ações</option>
            {ACOES.map((a) => <option key={a}>{a}</option>)}
          </select>
        </div>
        {!eventos ? <div className="carregando" style={{ minHeight: 200 }}><div className="spin" /></div> : (
          <div className="tabela-wrap">
            <table>
              <thead><tr><th>Quando</th><th>Ação</th><th>Item</th><th className="so-desk">Detalhe</th><th className="so-desk">Usuário</th></tr></thead>
              <tbody>
                {lista.map((e) => (
                  <tr key={e.id} onClick={() => e.item_id && abrirItem(e.item_id)}>
                    <td style={{ whiteSpace: 'nowrap' }}>{fmtData(e.created_at, true)}</td>
                    <td><span className="pill mute">{e.acao}</span></td>
                    <td>{e.itens?.equipamento || (e.acao === 'EXCLUSÃO' ? e.detalhe : '—')}<div className="t2">{e.itens?.codigo_almox && `cód. ${e.itens.codigo_almox}`}</div></td>
                    <td className="so-desk">{e.acao !== 'EXCLUSÃO' && e.detalhe}</td>
                    <td className="so-desk muted">{e.usuario}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {lista.length === 0 && <div className="vazio">Nenhum evento.</div>}
          </div>
        )}
      </div>
    </>
  );
}

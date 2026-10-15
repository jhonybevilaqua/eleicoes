import { useMemo } from 'react';
import { Package, CheckCircle2, ArrowUpRight, Wrench, Hourglass, AlertTriangle, ClipboardCheck, RefreshCw, Clock } from 'lucide-react';
import { useDados } from '../lib/dados';
import { useNav } from '../App';
import { contar, diasDesdeInspecao, fmtData, precisaReposicao, situacaoVida, ANO_ATUAL } from '../lib/util';
import type { Filtro } from './Inventario';

export function Painel() {
  const { itens, abertas, recarregar } = useDados();
  const { ir, abrirItem } = useNav();

  const k = useMemo(() => {
    const ativos = itens.filter((i) => i.status !== 'BAIXADO');
    const agora = Date.now();
    return {
      total: ativos.length,
      disp: ativos.filter((i) => i.status === 'DISPONIVEL').length,
      uso: ativos.filter((i) => i.status === 'EM_USO').length,
      manut: ativos.filter((i) => i.status === 'MANUTENCAO' || i.status === 'AVARIADO').length,
      vencida: ativos.filter((i) => situacaoVida(i) === 'vencida').length,
      vence: ativos.filter((i) => situacaoVida(i) === 'vence').length,
      repo: ativos.filter(precisaReposicao).length,
      insp: ativos.filter((i) => { const d = diasDesdeInspecao(i); return d == null || d > 90; }).length,
      atrasadas: abertas.filter((m) => m.previsao_retorno && new Date(m.previsao_retorno).getTime() < agora),
      porTipo: contar(ativos, (i) => i.tipo),
      porLocal: contar(ativos, (i) => i.localizacao).slice(0, 10),
      porMarca: contar(ativos.filter((i) => i.marca), (i) => i.marca).slice(0, 10),
      porEquip: contar(ativos, (i) => i.equipamento).slice(0, 10),
      vidaPorTipo: contar(ativos.filter((i) => situacaoVida(i) === 'vencida'), (i) => i.tipo),
    };
  }, [itens, abertas]);

  const kpi = (rot: string, val: number, Icone: typeof Package, cls: string, f: Filtro | null, det?: string) => (
    <button className={'card kpi ' + cls} onClick={() => f && ir('inventario', f)}>
      <div className="rot"><Icone size={15} /> {rot}</div>
      <div className="val">{val.toLocaleString('pt-BR')}</div>
      {det && <div className="det">{det}</div>}
    </button>
  );

  return (
    <>
      <div className="topo">
        <div>
          <h1>Painel do almoxarifado</h1>
          <p>Visão geral dos equipamentos técnicos · {new Date().toLocaleDateString('pt-BR', { dateStyle: 'long' })}</p>
        </div>
        <div className="acoes">
          <button className="btn" onClick={() => recarregar()}><RefreshCw size={15} /> Atualizar</button>
          <button className="btn prim" onClick={() => ir('movimentacoes')}><ArrowUpRight size={15} /> Registrar saída</button>
        </div>
      </div>

      <div className="kpis">
        {kpi('Itens ativos', k.total, Package, '', {})}
        {kpi('Disponíveis', k.disp, CheckCircle2, 'ok', { status: 'DISPONIVEL' }, pct(k.disp, k.total))}
        {kpi('Em uso / fora', k.uso, ArrowUpRight, 'info', { status: 'EM_USO' }, k.atrasadas.length ? `${k.atrasadas.length} com retorno atrasado` : undefined)}
        {kpi('Manutenção / avaria', k.manut, Wrench, 'warn', { status: 'MANUTENCAO,AVARIADO' })}
        {kpi('Vida útil vencida', k.vencida, Hourglass, 'bad', { alerta: 'vencida' }, `antes de ${ANO_ATUAL}`)}
        {kpi('Vida útil vencendo', k.vence, Clock, 'warn', { alerta: 'vence' }, `${ANO_ATUAL}–${ANO_ATUAL + 1}`)}
        {kpi('Precisam reposição', k.repo, AlertTriangle, 'bad', { alerta: 'reposicao' })}
        {kpi('Inspeção > 90 dias', k.insp, ClipboardCheck, 'warn', { alerta: 'inspecao' }, 'ou sem registro')}
      </div>

      {k.atrasadas.length > 0 && (
        <div className="card" style={{ marginBottom: 16 }}>
          <div className="card-head"><AlertTriangle size={16} color="var(--bad)" /><h2>Devoluções atrasadas</h2>
            <div className="acoes"><button className="btn sm" onClick={() => ir('movimentacoes')}>Ver todas</button></div></div>
          <div className="tabela-wrap">
            <table>
              <thead><tr><th>Equipamento</th><th>Com</th><th>Destino</th><th>Previsão</th></tr></thead>
              <tbody>
                {k.atrasadas.slice(0, 8).map((m) => (
                  <tr key={m.id} onClick={() => abrirItem(m.item_id)}>
                    <td><div className="t1">{m.itens?.equipamento}</div><div className="t2">cód. {m.itens?.codigo_almox || '—'}</div></td>
                    <td>{m.responsavel}<div className="t2">{m.setor}</div></td>
                    <td>{m.destino || '—'}</td>
                    <td className="atrasado">{fmtData(m.previsao_retorno, true)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="paineis">
        <Barras titulo="Itens por tipo" dados={k.porTipo} onClick={(v) => ir('inventario', { tipo: v })} />
        <Barras titulo="Vida útil vencida por tipo" dados={k.vidaPorTipo} cor="var(--bad)" onClick={(v) => ir('inventario', { tipo: v, alerta: 'vencida' })} />
        <Barras titulo="Localizações com mais itens" dados={k.porLocal} onClick={(v) => ir('inventario', { local: v })} />
        <Barras titulo="Marcas" dados={k.porMarca} onClick={(v) => ir('inventario', { q: v })} />
        <Barras titulo="Equipamentos em maior quantidade" dados={k.porEquip} onClick={(v) => ir('inventario', { q: v })} />
      </div>
    </>
  );
}

const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}% do total` : undefined);

function Barras({ titulo, dados, onClick, cor }: { titulo: string; dados: [string, number][]; onClick?: (v: string) => void; cor?: string }) {
  const max = Math.max(1, ...dados.map((d) => d[1]));
  return (
    <div className="card">
      <div className="card-head"><h2>{titulo}</h2></div>
      <div className="barras">
        {dados.length === 0 && <div className="muted">Nada por aqui.</div>}
        {dados.map(([rot, n]) => (
          <div key={rot} className={'barra' + (onClick ? ' clic' : '')} onClick={() => onClick?.(rot)} title={`${rot}: ${n}`}>
            <span className="rot">{rot}</span>
            <span className="trilho"><span className="ench" style={{ width: `${(n / max) * 100}%`, display: 'block', background: cor }} /></span>
            <span className="n">{n}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

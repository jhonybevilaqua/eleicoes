import { useEffect, useState, type FormEvent } from 'react';
import { Trash2, UserPlus } from 'lucide-react';
import { supabase, emailCorporativo } from '../lib/supabase';
import { useDados } from '../lib/dados';
import type { Papel, Usuario } from '../lib/types';

const PAPEIS: Record<Papel, string> = {
  admin: 'Administrador — tudo, inclusive usuários e importação',
  operador: 'Operador — cadastra, edita, saídas e devoluções',
  leitor: 'Leitor — somente consulta',
};

export function Usuarios() {
  const { email: eu, aviso } = useDados();
  const [lista, setLista] = useState<Usuario[]>([]);
  const [email, setEmail] = useState('');
  const [nome, setNome] = useState('');
  const [papel, setPapel] = useState<Papel>('operador');

  const carregar = () => supabase.from('usuarios').select('*').order('email').then(({ data }) => setLista((data as Usuario[]) || []));
  useEffect(() => { carregar(); }, []);

  async function adicionar(e: FormEvent) {
    e.preventDefault();
    const em = email.trim().toLowerCase();
    if (!emailCorporativo(em)) return aviso('Use um e-mail dos domínios da empresa', true);
    const { error } = await supabase.from('usuarios').upsert({ email: em, nome: nome.trim() || null, papel });
    if (error) return aviso(error.message, true);
    setEmail(''); setNome('');
    aviso('Usuário salvo');
    carregar();
  }

  async function mudar(u: Usuario, p: Papel) {
    const { error } = await supabase.from('usuarios').update({ papel: p }).eq('email', u.email);
    if (error) return aviso(error.message, true);
    carregar();
  }

  async function remover(u: Usuario) {
    if (!confirm(`Remover ${u.email}? A pessoa continua podendo entrar, mas só para consulta.`)) return;
    const { error } = await supabase.from('usuarios').delete().eq('email', u.email);
    if (error) return aviso(error.message, true);
    carregar();
  }

  return (
    <>
      <div className="topo"><div><h1>Usuários</h1>
        <p>Qualquer e-mail corporativo entra como <b>leitor</b>. Cadastre aqui quem pode operar o almoxarifado.</p></div></div>

      <form className="card card-pad" style={{ marginBottom: 16 }} onSubmit={adicionar}>
        <div className="grid-form" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', alignItems: 'end' }}>
          <label className="campo"><span>E-mail</span><input className="inp" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="nome@tvevangelizar.com.br" /></label>
          <label className="campo"><span>Nome</span><input className="inp" value={nome} onChange={(e) => setNome(e.target.value)} /></label>
          <label className="campo"><span>Papel</span>
            <select className="inp" value={papel} onChange={(e) => setPapel(e.target.value as Papel)}>
              {(Object.keys(PAPEIS) as Papel[]).map((p) => <option key={p} value={p}>{PAPEIS[p].split(' — ')[0]}</option>)}
            </select></label>
          <button className="btn prim"><UserPlus size={15} /> Adicionar</button>
        </div>
        <div className="muted" style={{ fontSize: 12, marginTop: 10 }}>{PAPEIS[papel]}</div>
      </form>

      <div className="card tabela-wrap">
        <table>
          <thead><tr><th>E-mail</th><th>Nome</th><th>Papel</th><th /></tr></thead>
          <tbody>
            {lista.map((u) => (
              <tr key={u.email} style={{ cursor: 'default' }}>
                <td>{u.email}</td>
                <td>{u.nome || '—'}</td>
                <td>
                  <select className="inp" style={{ width: 'auto', height: 30 }} value={u.papel} disabled={u.email === eu} onChange={(e) => mudar(u, e.target.value as Papel)}>
                    {(Object.keys(PAPEIS) as Papel[]).map((p) => <option key={p} value={p}>{PAPEIS[p].split(' — ')[0]}</option>)}
                  </select>
                </td>
                <td className="num">{u.email !== eu && <button className="btn sm icone perigo" onClick={() => remover(u)} aria-label="Remover"><Trash2 size={14} /></button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

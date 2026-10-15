import { useEffect, useState, type FormEvent } from 'react';
import { Trash2, UserPlus, KeyRound, X } from 'lucide-react';
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
  const [rsEmail, setRsEmail] = useState('');
  const [rsSenha, setRsSenha] = useState('');

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

  async function redefinir(e: FormEvent) {
    e.preventDefault();
    const { error } = await supabase.rpc('redefinir_senha', { alvo: rsEmail.trim().toLowerCase(), nova: rsSenha });
    if (error) return aviso(error.message, true);
    aviso(`Senha de ${rsEmail} redefinida. Informe a nova senha à pessoa.`);
    setRsEmail(''); setRsSenha('');
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

      <form className="card card-pad" style={{ marginBottom: 16 }} onSubmit={redefinir}>
        <h2 style={{ marginBottom: 12 }}>Redefinir senha</h2>
        <div className="grid-form" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', alignItems: 'end' }}>
          <label className="campo"><span>E-mail de quem esqueceu</span><input className="inp" type="email" required value={rsEmail} onChange={(e) => setRsEmail(e.target.value)} /></label>
          <label className="campo"><span>Nova senha (mín. 8)</span><input className="inp" type="text" required minLength={8} value={rsSenha} onChange={(e) => setRsSenha(e.target.value)} autoComplete="off" /></label>
          <button className="btn"><KeyRound size={15} /> Redefinir</button>
        </div>
        <div className="muted" style={{ fontSize: 12, marginTop: 10 }}>A pessoa entra com a nova senha e pode trocá-la em "Alterar senha".</div>
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

export function SenhaModal({ fechar }: { fechar: () => void }) {
  const { aviso } = useDados();
  const [s1, setS1] = useState('');
  const [s2, setS2] = useState('');
  const [salvando, setSalvando] = useState(false);

  async function salvar(e: FormEvent) {
    e.preventDefault();
    if (s1.length < 8) return aviso('A senha precisa ter pelo menos 8 caracteres', true);
    if (s1 !== s2) return aviso('As senhas não conferem', true);
    setSalvando(true);
    const { error } = await supabase.auth.updateUser({ password: s1 });
    setSalvando(false);
    if (error) return aviso(error.message, true);
    aviso('Senha alterada');
    fechar();
  }

  return (
    <div className="fundo centro" onClick={fechar}>
      <form className="modal" style={{ width: 'min(420px, 100%)' }} onClick={(e) => e.stopPropagation()} onSubmit={salvar}>
        <div className="d-head"><h2>Alterar senha</h2>
          <div className="acoes"><button type="button" className="btn icone" onClick={fechar} aria-label="Fechar"><X size={18} /></button></div></div>
        <div className="d-body">
          <label className="campo"><span>Nova senha (mín. 8 caracteres)</span><input className="inp" type="password" autoComplete="new-password" required autoFocus value={s1} onChange={(e) => setS1(e.target.value)} /></label>
          <label className="campo"><span>Repita a nova senha</span><input className="inp" type="password" autoComplete="new-password" required value={s2} onChange={(e) => setS2(e.target.value)} /></label>
        </div>
        <div className="d-foot">
          <button type="button" className="btn" onClick={fechar}>Cancelar</button>
          <button className="btn prim" disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</button>
        </div>
      </form>
    </div>
  );
}

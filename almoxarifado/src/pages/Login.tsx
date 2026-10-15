import { useState, type FormEvent } from 'react';
import { LogIn, UserPlus } from 'lucide-react';
import { supabase, emailCorporativo, configurado } from '../lib/supabase';
import { Logo } from '../Logo';
import { BotaoTema } from '../Tema';

export function Login() {
  const [modo, setModo] = useState<'entrar' | 'criar'>('entrar');
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [senha2, setSenha2] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [msg, setMsg] = useState<{ t: string; c: 'bad' | 'ok' | 'info' } | null>(null);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    const em = email.trim().toLowerCase();
    if (!emailCorporativo(em)) {
      return setMsg({ t: 'Use seu e-mail corporativo @tvevangelizar.com.br ou @evangelizarepreciso.com.br.', c: 'bad' });
    }
    if (modo === 'criar') {
      if (senha.length < 8) return setMsg({ t: 'A senha precisa ter pelo menos 8 caracteres.', c: 'bad' });
      if (senha !== senha2) return setMsg({ t: 'As senhas não conferem.', c: 'bad' });
    }
    setEnviando(true);
    setMsg(null);
    const { data, error } = modo === 'entrar'
      ? await supabase.auth.signInWithPassword({ email: em, password: senha })
      : await supabase.auth.signUp({ email: em, password: senha });
    setEnviando(false);
    if (error) return setMsg({ t: traduz(error.message), c: 'bad' });
    if (modo === 'criar' && !data.session) {
      setMsg({ t: 'Conta criada, mas o Supabase está exigindo confirmação por e-mail. Desative "Confirm email" (veja o README).', c: 'info' });
    }
  }

  const trocar = (m: typeof modo) => { setModo(m); setMsg(null); setSenha(''); setSenha2(''); };

  return (
    <div className="login">
      <div style={{ position: 'fixed', top: 16, right: 16 }}><BotaoTema /></div>
      <div className="card">
        <Logo />
        <div className="tit">
          <h1>Almoxarifado Técnico</h1>
          <p>Controle de equipamentos · Operações Técnicas</p>
        </div>
        {!configurado && (
          <div className="aviso warn">Configure VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY (veja o README).</div>
        )}
        <div className="chips" style={{ justifyContent: 'center' }}>
          <button type="button" className={'chip' + (modo === 'entrar' ? ' on' : '')} onClick={() => trocar('entrar')}>Entrar</button>
          <button type="button" className={'chip' + (modo === 'criar' ? ' on' : '')} onClick={() => trocar('criar')}>Primeiro acesso</button>
        </div>
        {msg && <div className={'aviso ' + msg.c}>{msg.t}</div>}
        <form className="stack" onSubmit={enviar}>
          <label className="campo">
            <span>E-mail corporativo</span>
            <input className="inp" type="email" autoComplete="email" required autoFocus placeholder="nome@tvevangelizar.com.br"
              value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          <label className="campo">
            <span>{modo === 'criar' ? 'Crie uma senha (mín. 8 caracteres)' : 'Senha'}</span>
            <input className="inp" type="password" required autoComplete={modo === 'criar' ? 'new-password' : 'current-password'}
              value={senha} onChange={(e) => setSenha(e.target.value)} />
          </label>
          {modo === 'criar' && (
            <label className="campo">
              <span>Repita a senha</span>
              <input className="inp" type="password" required autoComplete="new-password" value={senha2} onChange={(e) => setSenha2(e.target.value)} />
            </label>
          )}
          <button className="btn prim" disabled={enviando}>
            {modo === 'entrar' ? <><LogIn size={16} /> {enviando ? 'Entrando…' : 'Entrar'}</> : <><UserPlus size={16} /> {enviando ? 'Criando…' : 'Criar acesso'}</>}
          </button>
        </form>
        <div className="rod">
          Acesso restrito a colaboradores TV Evangelizar e Evangelizar é Preciso.
          {modo === 'entrar' && <><br />Esqueceu a senha? Peça ao administrador do almoxarifado para redefinir.</>}
        </div>
      </div>
    </div>
  );
}

function traduz(m: string) {
  if (/Invalid login credentials/i.test(m)) return 'E-mail ou senha incorretos.';
  if (/already registered|already exists/i.test(m)) return 'Este e-mail já tem acesso. Use a aba "Entrar".';
  if (/rate limit|security purposes/i.test(m)) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
  if (/restrito|Database error/i.test(m)) return 'E-mail não autorizado para este sistema.';
  if (/Password should/i.test(m)) return 'Senha fraca: use pelo menos 8 caracteres.';
  return m;
}

# Almoxarifado Técnico · TV Evangelizar

Sistema web de controle do almoxarifado técnico: inventário, saídas e devoluções,
inspeções, vida útil, linha do tempo de cada item e painel gerencial.

- **Front-end:** React + Vite (hospedado no Vercel)
- **Banco e login:** Supabase (Postgres + login com e-mail e senha, sem envio de e-mail)
- **Acesso:** somente e-mails `@tvevangelizar.com.br` e `@evangelizarepreciso.com.br`,
  barrado também no banco (trigger + RLS), não só na tela.

## Funcionalidades

| Tela | O que faz |
|---|---|
| Painel | KPIs (disponíveis, fora, manutenção, vida útil vencida/vencendo, reposição, inspeção > 90 dias), devoluções atrasadas, gráficos por tipo, local, marca e equipamento. Tudo clicável e leva ao inventário já filtrado. |
| Inventário | Busca instantânea (nome, código, patrimônio, série, marca, local), filtros, ordenação, exportar Excel, cadastrar, editar, duplicar, mudar status, "inspecionado hoje", seleção de vários itens para saída em lote. |
| Saídas e devoluções | Itens fora agora (atrasados em vermelho), nova saída com carrinho de itens (kit), devolução individual, em lote ou do kit inteiro, condição na volta (OK / avariado / manutenção), histórico e exportação. |
| Atividade | Log automático de tudo (cadastro, edição, inspeção, status, saída, devolução, exclusão), com usuário e data/hora. |
| Usuários (admin) | Define quem é admin, operador ou leitor. |
| Importar planilha (admin) | Lê o .xlsx do inventário, normaliza tipos, locais, datas e inspeções, e carrega (substituindo ou somando). |

**Acesso:** cada pessoa cria a própria senha em *Primeiro acesso* (só e-mails dos dois domínios).
Esqueceu a senha? O admin redefine em *Usuários → Redefinir senha*; depois a pessoa troca em *Alterar senha*.

**Papéis:** qualquer e-mail corporativo entra como *leitor* (só consulta).
*Operador* cadastra, edita e movimenta. *Admin* também exclui, gerencia usuários e importa.

## Implantação (≈ 15 min)

### 1. Supabase
1. Crie um projeto em <https://supabase.com> (plano free atende).
2. **SQL Editor → New query**: cole todo o `supabase/schema.sql` e rode.
3. Rode a linha do primeiro admin, com o seu e-mail:
   ```sql
   insert into public.usuarios (email, nome, papel)
   values ('seu.nome@tvevangelizar.com.br', 'Seu Nome', 'admin')
   on conflict (email) do update set papel = 'admin';
   ```
4. **Authentication → Sign In / Providers → Email**: mantenha *Email* ligado e **desligue
   "Confirm email"**. Assim ninguém precisa receber e-mail: a pessoa cria a senha no
   "Primeiro acesso" e já entra. Só os dois domínios corporativos conseguem criar conta
   (bloqueio no banco).
5. **Authentication → URL Configuration**: em *Site URL* coloque o endereço do Vercel.
6. **Project Settings → API**: copie a *Project URL* e a chave *anon public*.

### 2. Vercel
1. *Add New → Project* → importe este repositório.
2. **Root Directory:** `almoxarifado` (Framework: Vite, detectado sozinho).
3. **Environment Variables:**
   - `VITE_SUPABASE_URL` = Project URL
   - `VITE_SUPABASE_ANON_KEY` = chave anon public
4. Deploy.

### 3. Carregar os dados
Entre com o e-mail admin → **Importar planilha** → escolha o
`Inventário Almoxarifado Técnico 2026.xlsx` → *Substituir tudo* → Importar.

> A planilha **não** fica no repositório (que é público) — ela só é lida no navegador
> e gravada no seu banco Supabase.

## Desenvolvimento local
```bash
cd almoxarifado
cp .env.example .env    # preencha URL e chave
npm install
npm run dev
```

## Regras de cálculo
- **Fim da vida útil** = ano de entrada + vida útil (anos). "ANTERIOR A 2019" conta como 2019,
  então o vencimento real pode ser anterior ao exibido.
- **Vencendo** = termina no ano atual ou no próximo.
- **Precisa reposição** = observação/histórico com "AGUARDANDO REPOSIÇÃO" ou "NECESSIDADE DE REPOSIÇÃO".
- **Inspeção > 90 dias** = última inspeção há mais de 90 dias ou sem registro.

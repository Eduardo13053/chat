# MOOVE — versão corrigida

Projeto em PHP 8.1+, HTML/CSS/JavaScript e Supabase Auth/PostgreSQL.

## Aplicar a correção

1. Extraia o ZIP e abra a pasta `moove` no VS Code, ou clone este repositório e abra sua pasta raiz.
2. Se `config.php` não existir, copie `config.example.php` para `config.php`. Preencha `config.php` com a URL do seu Supabase, a chave **publishable ou anon** e a URL do site. Se já tem um `config.php` configurado, preserve seus valores. Não use service_role/secret.
3. No **SQL Editor do mesmo projeto Supabase**, execute o arquivo inteiro **`sql/00_instalar_ou_atualizar.sql`** como administrador. Ele reúne todas as funções e políticas atualizadas em uma transação. Se alguma instrução falhar, nada dessa transação será aplicado. O esquema base do TCC precisa existir; ele não veio no ZIP original.
4. Inicie o site:

```sh
php -S localhost:8000 router.php
```

5. Abra http://localhost:8000, entre novamente e teste suas operações.

Faça backup do banco antes de aplicar uma atualização em produção. O instalador mantém tabelas, usuários e registros existentes; atualiza funções, cria tabelas de aprovação quando ausentes e restringe escrita REST direta nas tabelas geridas pelo Moove. Outras aplicações que escrevem diretamente nessas tabelas precisam usar as funções autorizadas.

**Use apenas o instalador 00 para a atualização completa.** Os arquivos 01, 03, 04 e 05 contêm suas partes para consulta. Executar apenas 01 por cima de uma instalação completa restabelece versões anteriores de algumas funções.

## Configuração do ambiente

PHP 8.1+ com `curl`, `mbstring`, `openssl`, JSON e sessões habilitados. O servidor deve ter acesso HTTPS ao seu Supabase e certificados CA válidos. Não desative a verificação TLS para contornar erros de certificado.

Em Supabase → Authentication → URL Configuration, configure a URL do site e os redirecionamentos permitidos. Mantenha confirmação de e-mail habilitada. Configure SMTP para envio real de confirmação e recuperação de senha.

O cadastro Auth precisa ter um trigger do seu esquema base que crie `perfis` e `clientes`. A versão corrigida identifica quando esses registros faltam. O instalador não inventa registros em tabelas cuja estrutura completa não foi fornecida.

## Aprovações

Vendedores precisam de loja e endereço comercial/coleta. Entregadores precisam de CNH futura e veículo ativo. Um gestor legítimo precisa aprovar os cadastros antes das operações.

Para autorizar o primeiro gestor, confira o UUID da conta legítima, que precisa ter perfil ativo, e-mail confirmado e registro em `funcionarios`. Como administrador no SQL Editor:

```sql
INSERT INTO public.moove_funcionarios_autorizados(perfil_id)
VALUES ('UUID-DO-FUNCIONARIO-LEGITIMO')
ON CONFLICT DO NOTHING;
```

Não cadastre todos os usuários como funcionários. Revise funcionários de teste e políticas antigas com `sql/02_diagnostico.sql`.

## Verificação após instalar

- Cliente: criar endereço, definir principal, solicitar entrega, rastrear e cancelar quando permitido.
- Vendedor: cadastrar loja e coleta; gestor aprovar; conferir pedidos. Alterar nome/CNPJ exige aprovação novamente.
- Entregador: cadastrar conta, CNH e veículo; gestor aprovar; ficar disponível; assumir entrega e avançar os status; registrar comprovante.
- Pagamento: registrar intenção pendente; somente gestor confirma após conferir o recebimento externo.
- Outra conta e usuário deslogado devem continuar sem acesso aos dados privados.

## Diagnóstico

Leia **CORRECOES.md**. A mensagem antiga “Operação não concluída. Verifique os dados e as permissões” era um fallback para diversas falhas. Agora o site diferencia função ausente, esquema incompatível, permissão insuficiente, dados inválidos, confirmação de e-mail e erros operacionais conhecidos.

Execute `sql/02_diagnostico.sql` para conferir colunas, enums, triggers, RLS e permissões de funções. Os logs do PHP registram status/códigos do Supabase, sem imprimir tokens ou payloads de dados pessoais.

## Limitações

- Frete fixo demonstrativo de R$ 25,00; sem cálculo de rota.
- Pagamentos são registros demonstrativos: não geram Pix, não processam cartão e não movimentam dinheiro.
- Rastreamento por eventos; sem GPS.
- Verificação documental é manual.
- Recuperação suporta token de acesso no fragmento da URL (`type=recovery`). Templates personalizados com PKCE/token_hash exigem integração adicional.
- O banco real e seus triggers/políticas não puderam ser testados: `config.php` no arquivo recebido contém somente exemplos e o esquema base não foi enviado. Os testes locais usaram um esquema representativo e um serviço Auth/REST simulado. Veja TESTES.md.

## Hospedagem

Use `router.php` no servidor local. No Apache, habilite as regras `.htaccess` fornecidas. Em Nginx, permita HTTP apenas para `index.php`, `api.php` e os arquivos públicos de `assets/`; bloqueie configuração, bootstrap, SQL e documentos internos. Use HTTPS em produção.

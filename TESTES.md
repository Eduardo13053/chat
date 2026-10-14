# Verificação da versão corrigida

Testes executados em 14/10/2026:

| Verificação | Resultado |
| --- | --- |
| Sintaxe de todos os arquivos PHP, PHP 8.4.24 | Passou |
| Sintaxe JavaScript, Node.js 24 | Passou |
| Nove formulários em DOM simulado com respostas assíncronas | Passou |
| Bloqueio de envio duplicado, reset após salvar e renovação CSRF | Passou |
| Controles bloqueados quando painel operacional está indisponível | Passou |
| HTTP PHP com serviço Auth/REST HTTPS simulado | Passou |
| Configuração ausente gera JSON 503; chave secret é rejeitada | Passou |
| Arquivos internos bloqueados pelo router, métodos e CSRF | Passou |
| Login, cadastro com redirect, reset de senha e sessão | Passou |
| RPC com retorno numérico, mensagem de validação e erro de permissão | Passou |
| Erros de e-mail 429 são tratados | Passou |
| Instalador SQL completo em PostgreSQL local via PGlite | Passou |
| Reaplicação do instalador e consultas de diagnóstico | Passou |
| Conta só lê as próprias entregas/endereços; anônimo sem EXECUTE | Passou |
| Escrita direta bloqueada mesmo com políticas permissivas antigas | Passou |
| Cadastro/aprovação e alteração de CNPJ revogando aprovação | Passou |
| CNH sem validade rejeitada e disponibilidade exige aprovação | Passou |
| Criação, atribuição e transições da entrega | Passou |
| Conclusão por comprovante sem trigger automático | Passou |
| Pagamento duplicado e confirmação por conta comum rejeitados | Passou |

## Alcance dos testes

O esquema de teste foi construído a partir das tabelas e colunas exigidas pelo código. Foram usados IDs integer e timestamp sem timezone para exercitar as conversões de retorno. O serviço de autenticação foi simulado; não houve envio real de e-mail nem acesso ao banco do usuário.

Esses resultados verificam o projeto e o instalador no esquema representativo. Não comprovam compatibilidade com colunas, constraints, triggers, políticas legadas ou dados diferentes no seu Supabase real. O esquema completo do TCC e as credenciais reais não vieram no ZIP. Valide no seu projeto após executar o instalador e confira qualquer diferença com `sql/02_diagnostico.sql`.

Não foram feitos testes visuais em navegador real nem testes de Apache/Nginx. Foram verificadas as interações JavaScript no JSDOM e as rotas no servidor HTTP do PHP.

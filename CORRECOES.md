# Correções e aplicação

## O que causava a mensagem da imagem

Em `bootstrap.php`, a função `rpc()` usava a mesma mensagem para quase todos os erros retornados pelo Supabase. A imagem sozinha não identifica qual função/operação falhou. Funções não instaladas, colunas incompatíveis, falta de permissão e várias validações de negócio apareciam com o mesmo texto.

Agora há diagnóstico específico, sem expor detalhes internos do banco. As mensagens de negócio emitidas pelas funções Moove são reconhecidas. O instalador completo restabelece definições e permissões das RPCs; a leitura do cliente usa uma função que filtra os dados pelo UUID autenticado.

## Problemas corrigidos no código

- Formulários usavam `event.currentTarget` depois de `await`. O navegador já o havia zerado: salvar endereço, entrega, CNH, veículo e comprovante podia funcionar no banco e falhar ao limpar/recarregar a tela.
- Envios duplicados por clique repetido agora são bloqueados enquanto o formulário aguarda a resposta.
- Respostas RPC podem ser números, objetos, listas ou nulas. O gateway agora aceita esses formatos corretamente.
- CNPJ era validado mas ignorado na atualização da loja. Agora é atualizado; mudanças em nome/CNPJ retiram a aprovação anterior.
- Validação CNPJ não depende mais de uma função externa `validar_cnpj` que poderia faltar no banco.
- CNH com data nula e status de entrega nulo agora são rejeitados pelas funções SQL.
- Retorno de entrega/histórico usa conversões explícitas, evitando incompatibilidade entre IDs integer/bigint e timestamp/timestamptz.
- Entregas disponíveis incluem status e valor do frete; são filtradas por disponibilidade, aprovação, CNH e capacidade de veículo.
- Registro de comprovante finaliza a entrega mesmo se o trigger de finalização não estiver instalado; preserva a compatibilidade com o trigger existente.
- Leitura de endereços/entregas do cliente não depende das antigas políticas SELECT. A função exige conta ativa e confirmada e filtra pelo dono.
- Falha isolada no painel operacional deixa os dados do cliente acessíveis e exibe aviso; controles dependentes ficam desabilitados.
- Falhas de reenvio e recuperação de e-mail deixaram de ser ignoradas.
- Cadastro/reenvio usam a URL de retorno configurada. Reset de senha renova a sessão local e o CSRF.
- Respostas de configuração da API são JSON. URL/chave inválidas, extensões PHP ausentes e chave administrativa recebem instruções específicas.
- Logs não imprimem payloads/tokens. Exceções internas inesperadas não são enviadas integralmente ao navegador.
- RLS é habilitado e escrita direta é restringida nas tabelas geridas pelas RPCs, inclusive documentos/veículos que poderiam burlar aprovação via REST.
- Página com CSRF não fica em cache; regras Apache bloqueiam documentos internos.
- Instalador transacional e repetível reúne as partes 01/03/04/05 e atualiza o cache do PostgREST.

## Como usar

1. Use a pasta corrigida e preencha `config.php` com os valores públicos do **mesmo** projeto Supabase. Preserve seus valores locais já configurados.
2. Faça backup e execute **todo** `sql/00_instalar_ou_atualizar.sql` no SQL Editor como administrador.
3. Reinicie o PHP, abra a página e faça login novamente.
4. Execute o roteiro do README.

## Se o banco ainda apresentar erro

| Mensagem | Ação |
| --- | --- |
| Configure a URL/chave | Preencher `config.php` com URL e chave publishable/anon corretas. |
| Função ausente/desatualizada | Aplicar o instalador completo 00 no mesmo projeto. Conferir se o SQL terminou com sucesso. |
| Permissão do banco insuficiente | Aplicar 00 como administrador. Conferir proprietário/EXECUTE das funções no diagnóstico. |
| Estrutura não corresponde ao projeto | Executar 02 e comparar colunas/enums com as funções SQL. O esquema base não foi incluído no arquivo enviado. |
| Perfil/cliente ausente | Conferir o trigger de cadastro de `auth.users` e recuperar os registros conforme o esquema real. |
| Conta inativa/e-mail não confirmado | Regularizar o estado da conta ou confirmar o e-mail. |
| Aguarde aprovação | Completar o cadastro e pedir aprovação ao gestor legítimo. |
| Falha de conexão | Conferir URL, rede, projeto ativo e certificados CA do PHP. |

Não desative RLS nem coloque chave administrativa no site para esconder o erro. O instalador não remove políticas antigas de leitura; revise seu acesso antes de publicação, principalmente se funcionários de teste receberam privilégios amplos.

## O que não foi alterado remotamente

Nenhum banco ou site publicado foi modificado. O ZIP recebido só possui credenciais de exemplo; não fornece acesso administrativo real ao seu Supabase nem o esquema base completo. A permissão dada na conversa autoriza o trabalho, mas não estabelece uma conexão técnica com sua conta.

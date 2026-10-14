-- SOMENTE LEITURA. Execute como administrador no SQL Editor.
-- Mostra diferenças de esquema e permissões; não altera dados.
SELECT table_name,column_name,data_type,udt_name,is_nullable,column_default
FROM information_schema.columns WHERE table_schema='public'
AND table_name IN ('perfis','clientes','vendedores','entregadores','funcionarios','enderecos','perfil_enderecos','entregas','historico_entregas','documentos_entregadores','veiculos','comprovantes_entrega','pagamentos')
ORDER BY table_name,ordinal_position;

SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS argumentos,p.prosecdef AS security_definer,
 pg_get_userbyid(p.proowner) AS proprietario,
 has_function_privilege('authenticated',p.oid,'EXECUTE') AS usuario_pode_executar
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname LIKE 'moove_%' ORDER BY p.proname;

SELECT c.relname AS tabela,c.relrowsecurity AS rls_ativo
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' ORDER BY c.relname;

SELECT tablename,policyname,cmd,permissive,roles,qual,with_check
FROM pg_policies WHERE schemaname='public' ORDER BY tablename,cmd,policyname;

SELECT event_object_schema,event_object_table,trigger_name,action_timing,event_manipulation,action_statement
FROM information_schema.triggers WHERE event_object_schema IN ('public','auth')
ORDER BY event_object_schema,event_object_table,trigger_name;

SELECT t.typname,e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' ORDER BY t.typname,e.enumsortorder;

-- O esquema base precisa criar perfis/clientes no cadastro (trigger Auth).
SELECT u.id,u.email,u.email_confirmed_at,p.status,
 CASE WHEN p.id IS NULL THEN 'perfil ausente'
      WHEN p.status::text <> 'ativo' THEN 'perfil inativo'
      WHEN c.perfil_id IS NULL THEN 'cliente ausente' ELSE 'ok' END AS diagnostico
FROM auth.users u LEFT JOIN public.perfis p ON p.id=u.id
LEFT JOIN public.clientes c ON c.perfil_id=u.id ORDER BY u.created_at DESC;

-- Funcionários devem ser legítimos, sem promover todas as contas de teste.
SELECT f.perfil_id,p.nome FROM public.funcionarios f JOIN public.perfis p ON p.id=f.perfil_id;

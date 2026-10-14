<?php
/**
 * EXEMPLO OPCIONAL de conexão direta com PostgreSQL.
 * Não é usado pelo site. Use somente em scripts administrativos protegidos,
 * pois a conexão com usuário postgres pode ignorar RLS e auth.uid().
 * Defina as variáveis DB_* no ambiente do servidor; nunca no navegador.
 */
$host = getenv('DB_HOST');
$port = getenv('DB_PORT') ?: '5432';
$name = getenv('DB_NAME') ?: 'postgres';
$user = getenv('DB_USER');
$pass = getenv('DB_PASSWORD');
if (!$host || !$user || !$pass) {
    throw new RuntimeException('Configure DB_HOST, DB_USER e DB_PASSWORD no servidor.');
}
$dsn = "pgsql:host={$host};port={$port};dbname={$name};sslmode=require";
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,
]);

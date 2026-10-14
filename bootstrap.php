<?php
declare(strict_types=1);

$isHttps = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_name('moove_session');
    session_set_cookie_params([
        'lifetime' => 0, 'path' => '/', 'secure' => $isHttps,
        'httponly' => true, 'samesite' => 'Lax',
    ]);
    session_start();
}
$configPath = __DIR__ . '/config.php';
$config = is_file($configPath) ? require $configPath : [];
if (!is_array($config)) $config = [];

class MooveException extends RuntimeException {
    public function __construct(string $message, public readonly int $httpStatus = 400) {
        parent::__construct($message);
    }
}
function require_configuration(): void {
    global $config;
    foreach (['supabase_url', 'supabase_anon_key', 'app_url'] as $key) {
        if (!isset($config[$key]) || !is_string($config[$key]) || trim($config[$key]) === '' ||
            str_contains($config[$key], 'SEU-PROJETO') || str_contains($config[$key], 'COLE_SUA')) {
            throw new MooveException('Configure a URL e a chave pública do Supabase e a URL do site em config.php.', 503);
        }
    }
    $url = parse_url($config['supabase_url']);
    if (!$url || ($url['scheme'] ?? '') !== 'https' || empty($url['host']) ||
        isset($url['user']) || isset($url['pass']) || isset($url['query']) || isset($url['fragment'])) {
        throw new MooveException('A URL do Supabase em config.php deve ser uma URL HTTPS válida.', 503);
    }
    if (!filter_var($config['app_url'], FILTER_VALIDATE_URL) ||
        !in_array(parse_url($config['app_url'], PHP_URL_SCHEME), ['http', 'https'], true)) {
        throw new MooveException('A URL do site em config.php é inválida.', 503);
    }
    $key = trim($config['supabase_anon_key']);
    $parts = explode('.', $key);
    $payload = count($parts) === 3 ? base64_decode(strtr($parts[1], '-_', '+/'), true) : false;
    $claims = $payload !== false ? json_decode($payload, true) : null;
    if (str_starts_with($key, 'sb_secret_') || ($claims['role'] ?? '') === 'service_role') {
        throw new MooveException('Use a chave publishable ou anon em config.php. A chave administrativa não pode ser usada pelo site.', 503);
    }
    if (!str_starts_with($key, 'sb_publishable_') && ($claims['role'] ?? '') !== 'anon') {
        throw new MooveException('A chave do Supabase é inválida. Use a chave publishable ou anon do mesmo projeto.', 503);
    }
    foreach (['curl', 'mbstring', 'openssl'] as $extension) {
        if (!extension_loaded($extension)) throw new MooveException('Ative a extensão PHP ' . $extension . ' e reinicie o servidor.', 503);
    }
}
function exception_response(Throwable $e): never {
    if ($e instanceof MooveException) json_response(['error' => $e->getMessage(), 'csrf' => csrf_token()], $e->httpStatus);
    error_log('Moove erro interno: ' . get_class($e) . ' em ' . basename($e->getFile()) . ':' . $e->getLine());
    json_response(['error' => 'Erro interno do servidor. Consulte o log do PHP para diagnóstico.', 'csrf' => csrf_token()], 500);
}

function json_response(array $data, int $status = 200): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
function csrf_token(): string {
    return $_SESSION['csrf'] ??= bin2hex(random_bytes(32));
}
function require_csrf(array $data): void {
    if (!isset($data['csrf']) || !is_string($data['csrf']) || !hash_equals(csrf_token(), $data['csrf'])) {
        json_response(['error' => 'Sessão expirada. Atualize a página.', 'csrf' => csrf_token()], 419);
    }
}
function api_request(string $method, string $path, ?array $body = null, bool $authenticated = false, ?string $bearerToken = null): array {
    global $config;
    require_configuration();
    $base = rtrim($config['supabase_url'], '/');
    $headers = [
        'apikey: ' . $config['supabase_anon_key'],
        'Accept: application/json',
        'Content-Type: application/json',
        'Prefer: return=representation',
    ];
    // Chaves publishable (sb_publishable_...) não são JWTs: não usá-las como Bearer.
    if ($bearerToken !== null) {
        $headers[] = 'Authorization: Bearer ' . $bearerToken;
    } elseif ($authenticated) {
        $headers[] = 'Authorization: Bearer ' . ($_SESSION['access_token'] ?? '');
    } elseif (substr_count($config['supabase_anon_key'], '.') === 2) {
        // Compatibilidade com chave anon JWT legada.
        $headers[] = 'Authorization: Bearer ' . $config['supabase_anon_key'];
    }
    $ch = curl_init($base . '/' . ltrim($path, '/'));
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_FOLLOWLOCATION => false,
    ]);
    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body === [] ? (object)[] : $body, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
    }
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlCode = curl_errno($ch);
    curl_close($ch);
    if ($raw === false) {
        error_log('Moove conexão Supabase: cURL ' . $curlCode);
        throw new MooveException('Não foi possível conectar ao Supabase. Verifique a conexão, a URL do projeto e os certificados do PHP.', 503);
    }
    $decoded = json_decode($raw, true);
    if ($raw !== '' && json_last_error() !== JSON_ERROR_NONE) {
        throw new MooveException('O Supabase retornou uma resposta inválida. Verifique a URL do projeto.', 502);
    }
    return ['status' => $status, 'data' => $decoded ?? [], 'raw' => $raw];
}
function api_error(array $result, string $fallback): string {
    $d = is_array($result['data']) ? $result['data'] : [];
    $known = (string)($d['error_description'] ?? $d['msg'] ?? $d['message'] ?? '');
    $code = (string)($d['code'] ?? $d['error_code'] ?? '');
    // Registrar somente códigos, sem tokens, dados pessoais ou payloads.
    error_log('Moove Supabase HTTP ' . $result['status'] . ' código ' . preg_replace('/[^a-zA-Z0-9_]/', '', $code));
    if (in_array($known, [
        'Seu cadastro de cliente não foi criado. Verifique o trigger de cadastro no Supabase.',
        'Seu perfil não foi criado no banco. Verifique o trigger de cadastro no Supabase.',
        'Sua conta não está ativa. Procure o responsável pelo sistema.',
        'Acesso administrativo negado.',
        'Aguarde aprovação, cadastre CNH válida e veículo ativo.',
        'CNPJ inválido.',
        'Cadastre um endereço de destino válido.',
        'Cadastre-se como entregador.',
        'Carga acima da capacidade do veículo.',
        'Confirme seu e-mail para continuar.',
        'Conta não autorizada.',
        'Dados da entrega inválidos.',
        'Dados do veículo inválidos.',
        'Endereço inválido.',
        'Endereço não encontrado.',
        'Entrega não disponível para coleta.',
        'Entrega não disponível para pagamento.',
        'Entrega não encontrada.',
        'Entrega não está pronta para comprovação.',
        'Entregador indisponível ou não aprovado.',
        'Entregador precisa cadastrar CNH válida e veículo.',
        'Forma de pagamento inválida.',
        'Informe CNH numérica e validade futura.',
        'Informe o nome de quem recebeu.',
        'Informe somente os 4 últimos dígitos do documento.',
        'Já existe pagamento pendente ou pago.',
        'Nome do estabelecimento inválido.',
        'Não é possível cancelar esta entrega.',
        'Origem e destino precisam ser diferentes.',
        'Pagamento pendente não encontrado.',
        'Ponto de coleta indisponível.',
        'Tipo de cadastro inválido.',
        'Transição de status não permitida.',
        'Vendedor precisa cadastrar endereço de coleta.',
        'Veículo não autorizado.'
    ], true)) return $known;
    if (str_contains(strtolower($known), 'invalid login') || $code === 'invalid_credentials') return 'E-mail ou senha incorretos.';
    if (str_contains(strtolower($known), 'email not confirmed') || $code === 'email_not_confirmed') return 'Confirme seu e-mail antes de entrar.';
    if ($result['status'] === 429) return 'Muitas tentativas. Aguarde e tente novamente.';
    if (in_array($code, ['PGRST202', '42883'], true)) return 'Função do banco ausente ou desatualizada. Execute sql/00_instalar_ou_atualizar.sql no Supabase e tente novamente.';
    if (in_array($code, ['PGRST205', '42P01', '42703', '42804', '22P02'], true)) return 'A estrutura do banco não corresponde ao projeto. Consulte sql/02_diagnostico.sql e o guia CORRECOES.md.';
    if ($code === '42501') return 'Permissão do banco insuficiente. Atualize as funções com sql/00_instalar_ou_atualizar.sql; não desative as regras de acesso.';
    if ($code === '23505' || $result['status'] === 409) return 'Registro já existente ou conflitante.';
    if ($code === '23503') return 'O registro relacionado não existe mais. Atualize os dados e tente novamente.';
    if (in_array($code, ['23502', '23514', '22007', '22008'], true)) return 'Confira os campos obrigatórios e o formato dos dados informados.';
    if ($result['status'] === 401) return 'Sessão inválida ou expirada. Entre novamente e confira a chave do Supabase.';
    if ($result['status'] === 403) return 'Acesso negado. Verifique sua conta e confirmação de e-mail.';
    if ($result['status'] >= 500) return 'O serviço de dados está indisponível. Tente novamente em instantes.';
    return $fallback;
}
function upstream_exception(array $result, string $fallback): never {
    $status = match (true) {
        $result['status'] === 429 => 429,
        $result['status'] === 401 => 401,
        $result['status'] === 403 => 403,
        $result['status'] >= 500 => 503,
        default => 400,
    };
    throw new MooveException(api_error($result, $fallback), $status);
}
function save_auth(array $data): void {
    session_regenerate_id(true);
    $_SESSION['access_token'] = $data['access_token'];
    $_SESSION['refresh_token'] = $data['refresh_token'] ?? '';
    $_SESSION['expires_at'] = time() + max(60, (int)($data['expires_in'] ?? 3600)) - 60;
    $_SESSION['user_id'] = $data['user']['id'] ?? '';
    $_SESSION['user_email'] = $data['user']['email'] ?? '';
}
function logged_in(): bool {
    return !empty($_SESSION['access_token']) && !empty($_SESSION['user_id']);
}
function require_auth(): void {
    if (!logged_in()) json_response(['error' => 'Faça login para continuar.'], 401);
    if (time() >= (int)($_SESSION['expires_at'] ?? 0)) {
        $refresh = $_SESSION['refresh_token'] ?? '';
        if ($refresh === '') {
            unset($_SESSION['access_token'], $_SESSION['user_id']);
            json_response(['error' => 'Sessão expirada. Entre novamente.'], 401);
        }
        $result = api_request('POST', 'auth/v1/token?grant_type=refresh_token', ['refresh_token' => $refresh]);
        if ($result['status'] >= 300 || empty($result['data']['access_token'])) {
            unset($_SESSION['access_token'], $_SESSION['refresh_token'], $_SESSION['user_id']);
            json_response(['error' => 'Sessão expirada. Entre novamente.'], 401);
        }
        save_auth($result['data']);
    }
}
function postgrest_get(string $table, array $query): array {
    $result = api_request('GET', 'rest/v1/' . $table . '?' . http_build_query($query, '', '&', PHP_QUERY_RFC3986), null, true);
    if ($result['status'] >= 300) upstream_exception($result, 'Não foi possível carregar os dados.');
    return $result['data'];
}
function rpc(string $name, array $params): mixed {
    $result = api_request('POST', 'rest/v1/rpc/' . $name, $params, true);
    if ($result['status'] >= 300) upstream_exception($result, 'Não foi possível concluir a operação. Consulte o log do PHP para diagnóstico.');
    return $result['data'];
}

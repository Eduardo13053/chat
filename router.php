<?php
/** Roteador para o servidor de desenvolvimento do PHP. */
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
if ($path === '/' || $path === '/index.php') {
    require __DIR__ . '/index.php';
    return true;
}
if ($path === '/api.php') {
    require __DIR__ . '/api.php';
    return true;
}
if (preg_match('~^/assets/[a-zA-Z0-9._/-]+\.(css|js|png|svg|jpg|jpeg|webp)$~', $path)) {
    $file = realpath(__DIR__ . $path);
    $assets = realpath(__DIR__ . '/assets');
    if ($file && $assets && str_starts_with($file, $assets . DIRECTORY_SEPARATOR) && is_file($file)) return false;
}
http_response_code(404);
echo 'Página não encontrada.';
return true;

<?php
/** Copie para config.php. Nunca envie config.php ao GitHub. */
return [
    'supabase_url' => getenv('SUPABASE_URL') ?: 'https://SEU-PROJETO.supabase.co',
    'supabase_anon_key' => getenv('SUPABASE_ANON_KEY') ?: 'COLE_SUA_CHAVE_PUBLISHABLE_OU_ANON',
    'app_url' => getenv('APP_URL') ?: 'http://localhost:8000',
];

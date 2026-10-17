-- Stage 2: SET LOCAL とトランザクション（app_user で接続して実行）
\set ON_ERROR_STOP off
\pset pager off

\echo '=== Stage 2: SET LOCAL とトランザクション ==='
\echo ''
\echo '--- [1] 一度も設定していない接続では current_setting は NULL'
SELECT current_setting('app.current_org_id', true) IS NULL AS is_null;

\echo '--- [2] SET LOCAL はトランザクション内だけ有効'
BEGIN;
SET LOCAL app.current_org_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET LOCAL app.current_user_sub = 'dev-user-a';
SELECT current_setting('app.current_org_id', true) AS in_tx;
SELECT count(*) AS rows_in_tx FROM donations;
COMMIT;

\echo '--- [3] COMMIT 後: 値は空文字 ''''（NULL ではない！）→ NULLIF のおかげで 0件'
SELECT current_setting('app.current_org_id', true) = '' AS is_empty_string;
SELECT count(*) AS rows_after_commit FROM donations;

\echo '--- [4] ROLLBACK でも同じく消える'
BEGIN;
SET LOCAL app.current_org_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
ROLLBACK;
SELECT current_setting('app.current_org_id', true) AS after_rollback;

\echo '--- [5] 落とし穴: トランザクション外の SET LOCAL は WARNING だけ出て何も起きない'
\echo '        （pgx で BEGIN せずに SET LOCAL を投げると、このパターンになる）'
SET LOCAL app.current_org_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT count(*) AS rows FROM donations;

\echo '--- [6] 落とし穴: SET LOCAL はバインド変数($1)を使えない → set_config(name, $1, true) を使う'
PREPARE ng(text) AS SET LOCAL app.current_org_id = $1;
PREPARE ok(text) AS SELECT set_config('app.current_org_id', $1, true);
DEALLOCATE ok;

\echo '--- [7] NG例: LOCAL を付け忘れた SET は「接続」に残り続ける'
SET app.current_org_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET app.current_user_sub = 'dev-user-a';
BEGIN; SELECT count(*) AS request1_univ_a FROM donations; COMMIT;
\echo '    ↓ 同じ接続を、次は「大学Bのリクエスト」が使ったが設定を忘れた'
SELECT organization_id, count(*) AS leaked FROM donations GROUP BY 1;
\echo '    → 大学Aのデータが見えている = コネクションプール経由の漏洩'
RESET app.current_org_id;
RESET app.current_user_sub;

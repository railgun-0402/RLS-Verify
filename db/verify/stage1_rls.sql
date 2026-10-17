-- Stage 1: PostgreSQL の RLS を体験する（app_user で接続して実行）
\set ON_ERROR_STOP off
\pset pager off

\echo '=== Stage 1: RLS の基本 ==='
\echo ''
\echo '--- [0] 接続ロールの属性（rolsuper / rolbypassrls が true なら RLS は効かない）'
SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;

\echo '--- [1] テナント未設定で SELECT → 0件（fail closed）'
SELECT count(*) AS visible_rows FROM donations;

\echo '--- [2] 大学A として SELECT → 大学Aの行だけ（WHERE は書いていない）'
BEGIN;
SELECT set_config('app.current_org_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true) AS org,
       set_config('app.current_user_sub', 'dev-user-a', true) AS sub;
SELECT organization_id, donor_name, amount FROM donations ORDER BY id;

\echo '--- [3] WHERE で大学Bを明示しても 0件（ポリシー条件が AND で付く）'
SELECT count(*) AS b_rows FROM donations
WHERE organization_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

\echo '--- [4] 実行計画にポリシー条件が差し込まれていることを確認'
EXPLAIN (COSTS OFF) SELECT * FROM donations;

\echo '--- [5] 大学Bの行を INSERT → WITH CHECK 違反でエラーになるはず'
INSERT INTO donations (organization_id, donor_name, amount)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '侵入者', 1);
ROLLBACK;

\echo ''
\echo '補足: postgres(superuser) で同じ SELECT をすると全件見える。'
\echo '      アプリは必ず BYPASSRLS を持たない専用ロールで接続すること。'

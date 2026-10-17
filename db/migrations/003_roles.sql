-- psql -v app_password=... -v batch_password=... で渡す（Makefile 参照）
--
-- ロール設計
--   マイグレーション用（postgres / RDSマスター）: テーブルのオーナー。アプリからは使わない
--   app_user       : API が使う。RLS の対象。BYPASSRLS なし
--   batch_user     : 管理バッチが使う。全大学を「読むだけ」
--   ranking_reader : ログイン不可。全国ランキング関数の所有者としてだけ存在する

CREATE ROLE app_user   LOGIN PASSWORD :'app_password'   NOSUPERUSER NOBYPASSRLS;
CREATE ROLE batch_user LOGIN PASSWORD :'batch_password' NOSUPERUSER NOBYPASSRLS;
CREATE ROLE ranking_reader NOLOGIN NOSUPERUSER NOBYPASSRLS;

GRANT USAGE ON SCHEMA public TO app_user, batch_user, ranking_reader;

GRANT SELECT ON organizations TO app_user, batch_user, ranking_reader;
GRANT SELECT ON memberships   TO app_user;
GRANT SELECT, INSERT ON donations TO app_user;
GRANT USAGE ON SEQUENCE donations_id_seq TO app_user;
GRANT SELECT ON donations TO batch_user, ranking_reader;

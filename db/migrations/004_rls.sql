-- ========== ヘルパー関数 ==========
-- current_setting(name, true) は
--   ・一度も設定されていない接続では NULL
--   ・SET LOCAL / set_config(...,true) した後、トランザクション終了後は '' (空文字)
-- を返す。''::uuid はエラーになるので NULLIF で NULL に寄せ、「未設定なら0件」に倒す。
CREATE FUNCTION app_current_org_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid
$$;

CREATE FUNCTION app_current_user_sub() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.current_user_sub', true), '')
$$;

-- ========== donations ==========
ALTER TABLE donations ENABLE ROW LEVEL SECURITY;
-- FORCE を付けないとテーブルオーナーは RLS を素通りする
ALTER TABLE donations FORCE ROW LEVEL SECURITY;

-- app_user 用ポリシー（donations_tenant）は db/policies/*.sql で切り替える

-- バッチ・ランキング関数は全大学を読める（SELECT のみ）
CREATE POLICY donations_read_all ON donations
  AS PERMISSIVE FOR SELECT
  TO batch_user, ranking_reader
  USING (true);

-- ========== memberships ==========
-- 自分(sub)の所属行だけ見える。
-- 所属の登録は管理者(オーナー)が行う前提なので FORCE はしない。
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY memberships_self ON memberships
  AS PERMISSIVE FOR SELECT
  TO app_user
  USING (user_sub = (SELECT app_current_user_sub()));

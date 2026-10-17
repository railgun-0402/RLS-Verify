-- パターンB: 「大学ID」に加えて「そのユーザーが本当にその大学に所属しているか」も DB が確認する
--   ・アプリが所属チェックを忘れても、DB が最後の砦になる
--   ・アプリが DB に渡すのは「認証済みの sub」と「選択中の大学ID」だけ
DROP POLICY IF EXISTS donations_tenant ON donations;

CREATE POLICY donations_tenant ON donations
  AS PERMISSIVE FOR ALL
  TO app_user
  USING (
    organization_id = (SELECT app_current_org_id())
    AND EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.organization_id = donations.organization_id
        AND m.user_sub = (SELECT app_current_user_sub())
    )
  )
  WITH CHECK (
    organization_id = (SELECT app_current_org_id())
    AND EXISTS (
      SELECT 1 FROM memberships m
      WHERE m.organization_id = donations.organization_id
        AND m.user_sub = (SELECT app_current_user_sub())
    )
  );

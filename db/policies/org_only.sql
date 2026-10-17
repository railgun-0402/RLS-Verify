-- パターンA: 「アプリが設定した大学ID」だけを信じるポリシー
--   ・所属チェックはアプリ(Go)の責務
--   ・アプリが所属チェックを忘れる／ヘッダーの値をそのまま使うと、他大学が見えてしまう
DROP POLICY IF EXISTS donations_tenant ON donations;

CREATE POLICY donations_tenant ON donations
  AS PERMISSIVE FOR ALL
  TO app_user
  USING      (organization_id = (SELECT app_current_org_id()))
  WITH CHECK (organization_id = (SELECT app_current_org_id()));

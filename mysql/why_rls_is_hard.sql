-- MySQL で「RLS っぽいこと」をやろうとするとどうなるか
-- 実行: make mysql-demo  （--force でエラーが出ても続行する）

DROP TABLE IF EXISTS donations;
DROP VIEW IF EXISTS v_donations;
DROP FUNCTION IF EXISTS current_org;

CREATE TABLE donations (
  id              BIGINT AUTO_INCREMENT PRIMARY KEY,
  organization_id CHAR(36) NOT NULL,
  donor_name      VARCHAR(100) NOT NULL,
  amount          INT NOT NULL,
  INDEX (organization_id)
);
INSERT INTO donations (organization_id, donor_name, amount) VALUES
  ('A', '山田 太郎', 10000), ('A', '佐藤 花子', 5000), ('B', '高橋 次郎', 20000);

SELECT '--- [1] CREATE POLICY は存在しない → 構文エラー' AS step;
CREATE POLICY tenant ON donations USING (organization_id = 'A');

SELECT '--- [2] ビューの WHERE でユーザー変数を参照 → 禁止されている (ER_VIEW_SELECT_VARIABLE)' AS step;
SET @org_id = 'A';
CREATE VIEW v_donations AS SELECT * FROM donations WHERE organization_id = @org_id;

SELECT '--- [3] 抜け道: 関数で変数を包めばビューは作れる…' AS step;
CREATE FUNCTION current_org() RETURNS CHAR(36) NOT DETERMINISTIC NO SQL RETURN @org_id;
CREATE SQL SECURITY DEFINER VIEW v_donations AS
  SELECT * FROM donations WHERE organization_id = current_org()
  WITH CHECK OPTION;
SELECT * FROM v_donations;

SELECT '--- [4] …が、ベーステーブルを直接読めば当然すべて見える（FORCE 相当がない）' AS step;
SELECT * FROM donations;

SELECT '--- [5] ユーザー変数はセッション単位。COMMIT しても消えない（SET LOCAL 相当がない）' AS step;
START TRANSACTION;
SET @org_id = 'B';
COMMIT;
SELECT @org_id AS still_set_after_commit;

SELECT '--- [6] 関数がビュー条件に入ると、インデックスが効きにくく・行ごと評価になりやすい' AS step;
EXPLAIN SELECT * FROM v_donations;

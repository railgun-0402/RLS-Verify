-- RLS を有効にする前に投入する（RDS のマスターユーザーは superuser ではないため、
-- FORCE ROW LEVEL SECURITY 後はオーナーでも INSERT できなくなる）
INSERT INTO organizations (id, name) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '大学A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '大学B'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '大学C');

INSERT INTO donations (organization_id, donor_name, amount) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '山田 太郎', 10000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '佐藤 花子',  5000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '鈴木 一郎', 30000),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '高橋 次郎', 20000),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '田中 三郎',  8000),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '伊藤 四郎', 50000);

-- ローカル(AUTH_MODE=dev)用のユーザー
-- dev-user-c は「認証はできるが、どの大学にも所属していない人」
INSERT INTO memberships (user_sub, organization_id, role) VALUES
  ('dev-user-a', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'staff'),
  ('dev-user-b', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'staff');

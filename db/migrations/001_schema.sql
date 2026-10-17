-- 大学（テナント）
CREATE TABLE organizations (
  id   uuid PRIMARY KEY,
  name text NOT NULL
);

-- 「Cognito のユーザー(sub)が、どの大学に所属しているか」
-- 認証(Cognito)とは別に、所属(認可)の事実はアプリ側のDBで持つ
CREATE TABLE memberships (
  user_sub        text NOT NULL,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  role            text NOT NULL DEFAULT 'staff',
  PRIMARY KEY (user_sub, organization_id)
);

-- 全大学共通の寄付テーブル（organization_id で論理分離）
CREATE TABLE donations (
  id              bigserial PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  donor_name      text NOT NULL,
  amount          integer NOT NULL CHECK (amount > 0),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX donations_organization_id_idx ON donations (organization_id);

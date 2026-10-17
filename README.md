# RLS 技術検証ミニアプリ（Go / Echo / pgxpool / PostgreSQL RLS / Cognito）

## この検証で確かめること

1. PostgreSQL の RLS で、大学Aから大学Bの寄付が見えないこと
2. `SET LOCAL`（`set_config(..., true)`）がトランザクション終了で確実に消え、接続を使い回しても漏れないこと
3. SQL に `WHERE organization_id = ...` を書き忘れても分離されること
4. 通常 API は RLS で守りつつ、データが安全に集計できるロール設計
5. **「Cognito で認証済み」と「その大学に本当に所属している」は別物**で、RLS がどちらを守っているのかを理解すること
6. MySQL ではなぜ同じことが難しいのか

## 3つの層の役割

| 層 | 答える問い | このアプリでの実装 |
|---|---|---|
| 認証（Cognito） | あなたは誰？ | JWT を検証して `sub` を得る（`internal/auth`） |
| 所属の認可 | その大学に属している？ | `memberships` テーブルを確認（`ResolveTenant` ミドルウェア） |
| RLS | DB に渡された文脈に合う行だけ返す | `donations_tenant` ポリシー |

ポイントは、**RLS は「アプリが DB に伝えた文脈」を強制するだけ**だということです。
アプリがヘッダーの `X-Organization-Id` を所属確認せずに `app.current_org_id` に入れれば、
RLS はそれを正しい値として扱い、他大学のデータを返してしまいます。

そこでポリシーを 2 パターン用意しています。

- **パターンA `org_only`**: `organization_id = 設定された大学ID` だけを見る。所属確認はアプリの責務
- **パターンB `with_membership`**: 上記に加えて「設定された sub がその大学の `memberships` にいるか」も DB が確認する。アプリが所属チェックを書き忘れても DB が止める

## ディレクトリ構成

```
db/migrations/   スキーマ・シード・ロール・RLS・ランキング関数
db/policies/     donations_tenant ポリシー（パターンA / B を切り替え）
db/verify/       Stage 1, 2 の psql スクリプト
go/cmd/api       Echo の API（テナント認可 → Usecase → Repository）
go/cmd/stage3    pgxpool 最大1接続での交互アクセス検証
go/cmd/stage4    クロステナント集計・バッチ用ロールの検証
infra/           Terraform（Cognito User Pool + RDS for PostgreSQL）
mysql/           MySQL で RLS が難しい理由のデモ
scripts/         認証・所属・RLS のシナリオ curl
```

## ローカルで動かす

必要なもの: Docker, psql, Go 1.22+

```bash
make up
make migrate              # パターンA で初期化
cd go && go mod tidy && cd ..
```

### Stage 1: RLS を体験する

```bash
make stage1
```

期待結果: 未設定なら 0 件、大学A設定時は A の 3 件のみ、`WHERE` で B を指定しても 0 件、
B の行の INSERT は `new row violates row-level security policy` で失敗。
`EXPLAIN` にポリシー条件が差し込まれているのも確認できます。

### Stage 2: SET LOCAL とトランザクション

```bash
make stage2
```

ここで分かる落とし穴:

- COMMIT 後の `current_setting(..., true)` は NULL ではなく**空文字**。`''::uuid` はエラーになるので、ヘルパー関数で `NULLIF` している
- トランザクション外の `SET LOCAL` は WARNING だけで**何も起きない**（pgx で BEGIN し忘れると、これになる）
- `SET LOCAL` は `$1` を使えない。アプリでは `set_config(name, $1, true)` を使う
- `LOCAL` なしの `SET` は接続に残り、次のリクエストに漏れる

### Stage 3: Go + pgxpool で接続再利用

```bash
make stage3
```

`MaxConns=1` にして A/B を交互に実行します。`backend_pid` が全部同じ（同じ物理接続）でも、
毎回自分の大学の行しか見えないことを確認します。最後に、セッションレベルの `SET` を使うと
次のリクエストに大学Aのデータが漏れる NG 例も出力されます。

### Stage 4: クロステナント集計・管理バッチ

```bash
make stage4
```

| ロール | できること |
|---|---|
| `app_user` | 自大学の行だけ。全件は 0 件。ただし `reporting.national_ranking()` で**集計値だけ**取れる |
| `ranking_reader`（NOLOGIN） | ランキング関数の所有者。SECURITY DEFINER でこのロールの権限で集計する |
| `batch_user` | 全大学を読むだけ。INSERT 不可、`memberships` 不可 |

`BYPASSRLS` を持つロールを API から使える場所に置かない、というのが設計の軸です。

### 認証と所属の違いを体験する

```bash
AUTH_MODE=dev make run       # 別ターミナル
make scenarios               # パターンA のまま実行
make policy-membership
make scenarios               # パターンB で再実行し、シナリオ4 の結果を比べる
```

| # | シナリオ | パターンA | パターンB |
|---|---|---|---|
| 1 | user-a が大学Aを見る | 200・Aのみ | 200・Aのみ |
| 2 | user-a が大学Bを指定 | 403（アプリ） | 403（アプリ） |
| 3 | user-c（認証OK・所属なし） | 403（アプリ） | 403（アプリ） |
| 4 | **所属チェックなしの unsafe API** で user-a が大学B | **Bが見える（漏洩）** | **0件** |
| 5 | ヘッダーA・ボディBで INSERT | 403（WITH CHECK） | 403（WITH CHECK） |
| 6 | 全国ランキング | 集計値のみ | 集計値のみ |

シナリオ4 が今回の核心です。Cognito の認証は通っているし、RLS も有効。それでも漏れるのは、
RLS に渡した「大学ID」が検証されていない値だからです。

## AWS で動かす

### 1. インフラ作成

```bash
cd infra
terraform init
terraform apply \
  -var="my_ip_cidr=$(curl -s https://checkip.amazonaws.com)/32" \
  -var="db_master_password=<任意の強いパスワード>"

export POOL_ID=$(terraform output -raw user_pool_id)
export CLIENT_ID=$(terraform output -raw client_id)
export DB_HOST=$(terraform output -raw db_host)
cd ..
```

### 2. マイグレーション

```bash
export AWS_DB="PG_HOST=$DB_HOST PG_SSLMODE=require PG_ADMIN_USER=rls_admin PG_ADMIN_PASS=<マスターパスワード> APP_DB_PASSWORD=<app用> BATCH_DB_PASSWORD=<batch用>"
make migrate $AWS_DB
```

RDS のマスターユーザーは superuser ではありません。`FORCE ROW LEVEL SECURITY` を付けた
`donations` は、オーナーであるマスターユーザーで SELECT しても 0 件になることがあります
（`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;` で確認できます）。
ローカルの `postgres` は superuser なので全件見えます。この違い自体も良い学びになります。

### 3. Cognito ユーザー作成と所属登録

```bash
PASS='Passw0rd!rls'
for u in user-a user-b user-c; do
  aws cognito-idp admin-create-user --user-pool-id $POOL_ID --username $u --message-action SUPPRESS
  aws cognito-idp admin-set-user-password --user-pool-id $POOL_ID --username $u --password "$PASS" --permanent
done

sub_of() {
  aws cognito-idp admin-get-user --user-pool-id $POOL_ID --username "$1" \
    --query "UserAttributes[?Name=='sub'].Value" --output text
}

# user-c はわざと登録しない（認証はできるが所属がない人）
psql "postgres://rls_admin:<マスターパスワード>@$DB_HOST:5432/rlsdemo?sslmode=require" -c "
INSERT INTO memberships (user_sub, organization_id) VALUES
  ('$(sub_of user-a)', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('$(sub_of user-b)', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');"
```

### 4. API 起動とシナリオ実行

```bash
token_of() {
  aws cognito-idp initiate-auth --client-id $CLIENT_ID --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters USERNAME="$1",PASSWORD="$PASS" \
    --query AuthenticationResult.AccessToken --output text
}

# 別ターミナル
AUTH_MODE=cognito COGNITO_REGION=ap-northeast-1 COGNITO_USER_POOL_ID=$POOL_ID COGNITO_CLIENT_ID=$CLIENT_ID \
  make run $AWS_DB

export TOKEN_A=$(token_of user-a) TOKEN_C=$(token_of user-c)
make scenarios
make policy-membership $AWS_DB
make scenarios
```

Stage 1〜4 も `make stage1 $AWS_DB` のように RDS に対して実行できます。

### 5. 片付け

```bash
cd infra && terraform destroy -var="my_ip_cidr=0.0.0.0/32" -var="db_master_password=x"
```

### なぜ Cognito のカスタム属性に大学IDを入れないのか

`custom:organization_id` をトークンに入れて、それを RLS に渡す設計もよく見かけます。
今回あえて `memberships` テーブルにしている理由は次の通りです。

- アプリクライアントの書き込み可能属性に含まれていると、**ユーザー自身が UpdateUserAttributes で書き換えられる**
- 所属の変更（異動・退職）がトークン失効まで反映されない
- 複数大学に所属するケースを表現しにくい

使う場合は、書き込み権限をアプリクライアントから外し、Pre Token Generation Lambda で
DB の所属情報から付与するなど、「ユーザーが値を制御できない」状態を担保する必要があります。

## MySQL で RLS が難しい理由

```bash
make mysql-demo
```

| 観点 | PostgreSQL | MySQL |
|---|---|---|
| 行レベルポリシー | `CREATE POLICY` がある | **機能自体がない** |
| テーブルオーナー・全ロールへの強制 | `FORCE ROW LEVEL SECURITY` | なし。ベーステーブル権限があれば素通り |
| トランザクションローカルな変数 | `SET LOCAL` / `set_config(..., true)` | なし。ユーザー変数はセッション単位で COMMIT 後も残る |
| ビューでの代用 | 不要 | ビュー定義でユーザー変数を参照できない。関数で包む抜け道はあるが、インデックスが効きにくい・行ごとの評価になりやすい |
| 書き込み制御 | `WITH CHECK` | ビューの `WITH CHECK OPTION` で近いことはできるが、更新可能ビューの制約が多い |

結果として MySQL では、テナント分離は次のどれかに寄ります。

- **アプリ層で強制**（ORM のグローバルスコープ、リポジトリ層で必ず条件を付ける等）。WHERE の書き忘れがそのまま漏洩になる。Stage 3 で検証した「書き忘れても DB が守る」が成り立たない
- **DB / スキーマをテナントごとに分ける**。分離は強いが、今回の全国ランキングのような横断集計が重くなる
- **ビュー + 関数 + 権限設計**で近似する。全テーブルに漏れなく適用し、接続ごとの変数リセットをアプリで保証する必要がある

## 本番に向けたメモ

- アプリの接続ロールに `BYPASSRLS` / superuser を絶対に使わない。マイグレーション用とアプリ用を分ける
- ポリシー内の `current_setting` はヘルパー関数を `(SELECT ...)` で包み、行ごとではなく 1 回の評価にする
- `organization_id` には必ずインデックスを張る（パターンB では `memberships` の主キーも効く）
- 接続を返却する前に設定を消したい場合は、pgxpool の `AfterRelease` で `RESET ALL` / `DISCARD ALL` を流す方法もあるが、トランザクションローカルに統一するほうが単純
- パスワードは Secrets Manager 等で管理する

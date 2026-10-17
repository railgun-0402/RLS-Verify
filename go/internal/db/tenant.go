package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Tenant は 1 リクエスト分の「誰が・どの大学として」アクセスしているか。
type Tenant struct {
	OrgID   string // 選択中の大学 (organizations.id)
	UserSub string // Cognito で認証済みのユーザー (sub)
}

// WithTenant はトランザクションを開始し、トランザクションローカルにテナント情報を設定してから fn を実行する。
//
//   - set_config(name, value, true) は SET LOCAL と同じ効果。COMMIT / ROLLBACK で自動的に消えるので、
//     プールに返した接続に設定が残らない。
//   - SET LOCAL は $1 のようなバインド変数を受け付けないため set_config を使う
//     （文字列連結で SET LOCAL を組み立てると SQL インジェクションの穴になる）。
func WithTenant(ctx context.Context, pool *pgxpool.Pool, t Tenant, fn func(tx pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`SELECT set_config('app.current_org_id', $1, true),
			        set_config('app.current_user_sub', $2, true)`,
			t.OrgID, t.UserSub,
		); err != nil {
			return fmt.Errorf("set tenant context: %w", err)
		}
		return fn(tx)
	})
}

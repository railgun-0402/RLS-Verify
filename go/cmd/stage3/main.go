// Stage 3: Go + pgxpool で接続再利用してもテナントが漏れないことを確認する。
//
//	DATABASE_URL=postgres://app_user:...@localhost:5432/rlsdemo go run ./cmd/stage3
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"sort"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/example/rls-verify/internal/db"
	"github.com/example/rls-verify/internal/repository"
)

const (
	orgA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	orgB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
)

func main() {
	ctx := context.Background()

	cfg, err := pgxpool.ParseConfig(os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	cfg.MaxConns = 1 // 全リクエストが「同じ物理接続」を使い回す状況を強制する
	cfg.MinConns = 1
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	tenants := []db.Tenant{
		{OrgID: orgA, UserSub: "dev-user-a"},
		{OrgID: orgB, UserSub: "dev-user-b"},
	}

	fmt.Println("=== [OK] WithTenant（トランザクションローカル）で大学A/Bを交互に実行 ===")
	for i := 0; i < 6; i++ {
		t := tenants[i%2]
		err := db.WithTenant(ctx, pool, t, func(tx pgx.Tx) error {
			pid, err := backendPID(ctx, tx)
			if err != nil {
				return err
			}
			ds, err := repository.ListDonations(ctx, tx) // WHERE なし
			if err != nil {
				return err
			}
			fmt.Printf("req#%d tenant=%s backend_pid=%d rows=%d orgs=%v\n",
				i+1, short(t.OrgID), pid, len(ds), orgsOf(ds))
			return nil
		})
		if err != nil {
			log.Fatal(err)
		}
	}
	fmt.Println("→ backend_pid が同じ = 同じ接続。それでも毎回自分の大学の行しか見えない")

	fmt.Println("\n=== [OK] テナント設定を忘れたリクエスト ===")
	ds, err := repository.ListDonations(ctx, pool)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("rows=%d （前のリクエストの設定は COMMIT で消えているので 0件 = fail closed）\n", len(ds))

	fmt.Println("\n=== [NG] セッションレベルの SET（is_local=false）を使った場合 ===")
	conn, err := pool.Acquire(ctx)
	if err != nil {
		log.Fatal(err)
	}
	if _, err := conn.Exec(ctx,
		`SELECT set_config('app.current_org_id', $1, false), set_config('app.current_user_sub', $2, false)`,
		orgA, "dev-user-a"); err != nil {
		log.Fatal(err)
	}
	ds, _ = repository.ListDonations(ctx, conn)
	fmt.Printf("大学Aのリクエスト: rows=%d orgs=%v\n", len(ds), orgsOf(ds))
	conn.Release() // 設定が残ったままプールへ返却

	conn, err = pool.Acquire(ctx)
	if err != nil {
		log.Fatal(err)
	}
	ds, _ = repository.ListDonations(ctx, conn)
	fmt.Printf("大学Bのリクエスト（設定を忘れた）: rows=%d orgs=%v  ← 大学Aのデータが漏洩！\n", len(ds), orgsOf(ds))

	// 後片付け
	for _, q := range []string{"RESET app.current_org_id", "RESET app.current_user_sub"} {
		if _, err := conn.Exec(ctx, q); err != nil {
			log.Fatal(err)
		}
	}
	conn.Release()
}

func backendPID(ctx context.Context, q repository.Querier) (int32, error) {
	var pid int32
	err := q.QueryRow(ctx, "SELECT pg_backend_pid()").Scan(&pid)
	return pid, err
}

func orgsOf(ds []repository.Donation) []string {
	set := map[string]struct{}{}
	for _, d := range ds {
		set[short(d.OrganizationID)] = struct{}{}
	}
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func short(orgID string) string {
	switch orgID {
	case orgA:
		return "A"
	case orgB:
		return "B"
	case "cccccccc-cccc-cccc-cccc-cccccccccccc":
		return "C"
	}
	return orgID
}

// Stage 4: クロステナント集計・管理バッチのロール／権限設計を確認する。
//
//	DATABASE_URL=postgres://app_user:...       （API と同じ app_user）
//	BATCH_DATABASE_URL=postgres://batch_user:... （管理バッチ用）
//	go run ./cmd/stage4
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/example/rls-verify/internal/repository"
)

func main() {
	ctx := context.Background()

	app := mustPool(ctx, "DATABASE_URL")
	defer app.Close()
	batch := mustPool(ctx, "BATCH_DATABASE_URL")
	defer batch.Close()

	fmt.Println("=== app_user ===")

	var n int
	if err := app.QueryRow(ctx, "SELECT count(*) FROM donations").Scan(&n); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("[1] テナント未設定で全件 SELECT: %d 件（生データは見えない）\n", n)

	rows, err := repository.NationalRanking(ctx, app)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("[2] reporting.national_ranking()（SECURITY DEFINER）経由なら集計値だけ取れる:")
	for i, r := range rows {
		fmt.Printf("    %d位 %s 合計=%d円 件数=%d\n", i+1, r.OrganizationName, r.TotalAmount, r.DonationCount)
	}

	fmt.Println("\n=== batch_user ===")

	if err := batch.QueryRow(ctx, "SELECT count(*) FROM donations").Scan(&n); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("[3] 全大学の生データを読める: %d 件（ポリシー donations_read_all）\n", n)

	_, err = batch.Exec(ctx,
		`INSERT INTO donations (organization_id, donor_name, amount)
		 VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'バッチ', 1)`)
	fmt.Printf("[4] 書き込みは拒否される: %v\n", err)

	_, err = batch.Exec(ctx, "SELECT * FROM memberships")
	fmt.Printf("[5] 所属情報は見られない: %v\n", err)
}

func mustPool(ctx context.Context, env string) *pgxpool.Pool {
	dsn := os.Getenv(env)
	if dsn == "" {
		log.Fatalf("env %s is required", env)
	}
	p, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatal(err)
	}
	return p
}

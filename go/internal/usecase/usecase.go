package usecase

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/example/rls-verify/internal/db"
	"github.com/example/rls-verify/internal/repository"
)

type Usecase struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Usecase { return &Usecase{pool: pool} }

func (u *Usecase) ListDonations(ctx context.Context, t db.Tenant) ([]repository.Donation, error) {
	var out []repository.Donation
	err := db.WithTenant(ctx, u.pool, t, func(tx pgx.Tx) error {
		var err error
		out, err = repository.ListDonations(ctx, tx)
		return err
	})
	return out, err
}

func (u *Usecase) CreateDonation(ctx context.Context, t db.Tenant, orgID, donorName string, amount int32) (repository.Donation, error) {
	var out repository.Donation
	err := db.WithTenant(ctx, u.pool, t, func(tx pgx.Tx) error {
		var err error
		out, err = repository.CreateDonation(ctx, tx, orgID, donorName, amount)
		return err
	})
	return out, err
}

// IsMember は「認証済みユーザーが、その大学に本当に所属しているか」を確認する（アプリ側の認可）。
func (u *Usecase) IsMember(ctx context.Context, userSub, orgID string) (bool, error) {
	var ok bool
	err := db.WithTenant(ctx, u.pool, db.Tenant{UserSub: userSub}, func(tx pgx.Tx) error {
		var err error
		ok, err = repository.IsMember(ctx, tx, userSub, orgID)
		return err
	})
	return ok, err
}

// NationalRanking はテナント設定なしで呼ぶ。生データではなく集計値だけが返る。
func (u *Usecase) NationalRanking(ctx context.Context) ([]repository.RankingRow, error) {
	return repository.NationalRanking(ctx, u.pool)
}

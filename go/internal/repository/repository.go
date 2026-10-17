package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Querier は pgx.Tx / *pgxpool.Pool / *pgxpool.Conn のどれでも受け取れるようにするための interface。
type Querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type Donation struct {
	ID             int64     `json:"id"`
	OrganizationID string    `json:"organization_id"`
	DonorName      string    `json:"donor_name"`
	Amount         int32     `json:"amount"`
	CreatedAt      time.Time `json:"created_at"`
}

// ListDonations は寄付一覧を返す。
// 検証のため WHERE organization_id = ... を「あえて」書いていない。分離は RLS に任せる。
func ListDonations(ctx context.Context, q Querier) ([]Donation, error) {
	rows, err := q.Query(ctx, `
		SELECT id, organization_id::text, donor_name, amount, created_at
		FROM donations
		ORDER BY id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Donation])
}

func CreateDonation(ctx context.Context, q Querier, orgID, donorName string, amount int32) (Donation, error) {
	rows, err := q.Query(ctx, `
		INSERT INTO donations (organization_id, donor_name, amount)
		VALUES ($1, $2, $3)
		RETURNING id, organization_id::text, donor_name, amount, created_at`,
		orgID, donorName, amount)
	if err != nil {
		return Donation{}, err
	}
	return pgx.CollectOneRow(rows, pgx.RowToStructByPos[Donation])
}

// IsMember はユーザーがその大学に所属しているかを返す。
// memberships にも RLS（自分の sub の行だけ見える）がかかっているので、
// app.current_user_sub を設定したトランザクション内で呼ぶこと。
func IsMember(ctx context.Context, q Querier, userSub, orgID string) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM memberships
			WHERE user_sub = $1 AND organization_id = $2
		)`, userSub, orgID).Scan(&ok)
	return ok, err
}

type RankingRow struct {
	OrganizationName string `json:"organization_name"`
	TotalAmount      int64  `json:"total_amount"`
	DonationCount    int64  `json:"donation_count"`
}

// NationalRanking は SECURITY DEFINER 関数経由で全国ランキング（集計値のみ）を取得する。
func NationalRanking(ctx context.Context, q Querier) ([]RankingRow, error) {
	rows, err := q.Query(ctx, `
		SELECT organization_name, total_amount, donation_count
		FROM reporting.national_ranking()`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[RankingRow])
}

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	"github.com/example/rls-verify/internal/auth"
	"github.com/example/rls-verify/internal/handler"
	"github.com/example/rls-verify/internal/usecase"
)

func main() {
	ctx := context.Background()

	cfg, err := pgxpool.ParseConfig(mustEnv("DATABASE_URL")) // app_user で接続すること
	if err != nil {
		log.Fatal(err)
	}
	if v := os.Getenv("DB_MAX_CONNS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			log.Fatalf("DB_MAX_CONNS: %v", err)
		}
		cfg.MaxConns = int32(n)
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	var authn auth.Authenticator
	switch os.Getenv("AUTH_MODE") {
	case "cognito":
		authn, err = auth.NewCognitoVerifier(ctx,
			mustEnv("COGNITO_REGION"), mustEnv("COGNITO_USER_POOL_ID"), mustEnv("COGNITO_CLIENT_ID"))
		if err != nil {
			log.Fatal(err)
		}
		log.Println("AUTH_MODE=cognito")
	default:
		authn = auth.DevAuthenticator{}
		log.Println(`AUTH_MODE=dev（"Authorization: Bearer dev:<sub>" で認証。ローカル専用）`)
	}

	uc := usecase.New(pool)
	h := handler.New(uc)

	e := echo.New()
	e.HideBanner = true
	e.Use(middleware.Logger(), middleware.Recover())

	e.GET("/healthz", func(c echo.Context) error { return c.String(http.StatusOK, "ok") })

	v1 := e.Group("/v1", handler.Authenticate(authn))

	// 正しい API: 認証 → 所属チェック → RLS
	withMembership := handler.ResolveTenant(uc, true)
	v1.GET("/donations", h.ListDonations, withMembership)
	v1.POST("/donations", h.CreateDonation, withMembership)

	// 検証用: 所属チェックを「書き忘れた」API（認証 → RLS）
	v1.GET("/unsafe/donations", h.ListDonations, handler.ResolveTenant(uc, false))

	// クロステナント集計: 認証だけで、集計値のみ返す
	v1.GET("/ranking", h.NationalRanking)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	e.Logger.Fatal(e.Start(":" + port))
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("env %s is required", k)
	}
	return v
}

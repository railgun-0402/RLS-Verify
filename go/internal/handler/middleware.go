package handler

import (
	"net/http"
	"regexp"
	"strings"

	"github.com/labstack/echo/v4"

	"github.com/example/rls-verify/internal/auth"
	"github.com/example/rls-verify/internal/db"
	"github.com/example/rls-verify/internal/usecase"
)

const (
	keySub    = "sub"
	keyTenant = "tenant"
)

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// Authenticate: 認証（あなたは誰？）。Cognito のトークンを検証して sub を取り出すだけ。
func Authenticate(a auth.Authenticator) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			token, ok := strings.CutPrefix(c.Request().Header.Get("Authorization"), "Bearer ")
			if !ok || token == "" {
				return echo.NewHTTPError(http.StatusUnauthorized, "missing bearer token")
			}
			sub, err := a.Authenticate(c.Request().Context(), token)
			if err != nil {
				return echo.NewHTTPError(http.StatusUnauthorized, "invalid token")
			}
			c.Set(keySub, sub)
			return next(c)
		}
	}
}

// ResolveTenant: テナント解決と認可（その大学に属している？）。
//
// checkMembership=false は「所属チェックを書き忘れた API」を再現するための検証用スイッチ。
// その場合でも RLS ポリシーがパターンB(with_membership)なら DB 側で止まる。
func ResolveTenant(uc *usecase.Usecase, checkMembership bool) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			orgID := c.Request().Header.Get("X-Organization-Id")
			if !uuidRe.MatchString(orgID) {
				return echo.NewHTTPError(http.StatusBadRequest, "X-Organization-Id must be a UUID")
			}
			sub, _ := c.Get(keySub).(string)

			if checkMembership {
				ok, err := uc.IsMember(c.Request().Context(), sub, orgID)
				if err != nil {
					return err
				}
				if !ok {
					return echo.NewHTTPError(http.StatusForbidden, "not a member of this organization")
				}
			}

			c.Set(keyTenant, db.Tenant{OrgID: orgID, UserSub: sub})
			return next(c)
		}
	}
}

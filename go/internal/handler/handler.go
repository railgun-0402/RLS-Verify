package handler

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"

	"github.com/example/rls-verify/internal/db"
	"github.com/example/rls-verify/internal/usecase"
)

type Handler struct {
	uc *usecase.Usecase
}

func New(uc *usecase.Usecase) *Handler { return &Handler{uc: uc} }

func (h *Handler) ListDonations(c echo.Context) error {
	t := c.Get(keyTenant).(db.Tenant)
	ds, err := h.uc.ListDonations(c.Request().Context(), t)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]any{
		"user_sub":         t.UserSub,
		"requested_org_id": t.OrgID,
		"visible_rows":     len(ds),
		"donations":        ds,
	})
}

type createDonationRequest struct {
	DonorName string `json:"donor_name"`
	Amount    int32  `json:"amount"`
	// 省略時はヘッダーの大学。わざと別の大学を入れて WITH CHECK を体験できるようにしている
	OrganizationID string `json:"organization_id"`
}

func (h *Handler) CreateDonation(c echo.Context) error {
	t := c.Get(keyTenant).(db.Tenant)

	var req createDonationRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "invalid body")
	}
	if req.DonorName == "" || req.Amount <= 0 {
		return echo.NewHTTPError(http.StatusBadRequest, "donor_name and positive amount are required")
	}
	orgID := req.OrganizationID
	if orgID == "" {
		orgID = t.OrgID
	}
	if !uuidRe.MatchString(orgID) {
		return echo.NewHTTPError(http.StatusBadRequest, "organization_id must be a UUID")
	}

	d, err := h.uc.CreateDonation(c.Request().Context(), t, orgID, req.DonorName, req.Amount)
	if err != nil {
		// RLS の WITH CHECK 違反は SQLSTATE 42501 (insufficient_privilege)
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "42501" {
			return echo.NewHTTPError(http.StatusForbidden, "blocked by RLS: "+pgErr.Message)
		}
		return err
	}
	return c.JSON(http.StatusCreated, d)
}

func (h *Handler) NationalRanking(c echo.Context) error {
	rows, err := h.uc.NationalRanking(c.Request().Context())
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, rows)
}

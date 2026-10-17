package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/lestrrat-go/jwx/v2/jwk"
	"github.com/lestrrat-go/jwx/v2/jwt"
)

// Authenticator はトークンを検証し「誰か (sub)」だけを返す。
// ここで分かるのは “本人であること” まで。“どの大学に所属しているか” は分からない。
type Authenticator interface {
	Authenticate(ctx context.Context, token string) (sub string, err error)
}

// ---------- ローカル検証用 ----------

// DevAuthenticator は "dev:<sub>" 形式のトークンをそのまま sub とみなす。ローカル専用。
type DevAuthenticator struct{}

func (DevAuthenticator) Authenticate(_ context.Context, token string) (string, error) {
	sub, ok := strings.CutPrefix(token, "dev:")
	if !ok || sub == "" {
		return "", errors.New(`dev token must be "dev:<sub>"`)
	}
	return sub, nil
}

// ---------- Cognito ----------

// CognitoVerifier は Cognito User Pool のアクセストークンを JWKS で検証する。
type CognitoVerifier struct {
	issuer   string
	clientID string
	jwksURL  string
	cache    *jwk.Cache
}

func NewCognitoVerifier(ctx context.Context, region, userPoolID, clientID string) (*CognitoVerifier, error) {
	issuer := fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s", region, userPoolID)
	jwksURL := issuer + "/.well-known/jwks.json"

	cache := jwk.NewCache(ctx)
	if err := cache.Register(jwksURL); err != nil {
		return nil, fmt.Errorf("register jwks: %w", err)
	}
	if _, err := cache.Refresh(ctx, jwksURL); err != nil {
		return nil, fmt.Errorf("fetch jwks: %w", err)
	}
	return &CognitoVerifier{issuer: issuer, clientID: clientID, jwksURL: jwksURL, cache: cache}, nil
}

func (v *CognitoVerifier) Authenticate(ctx context.Context, token string) (string, error) {
	keys, err := v.cache.Get(ctx, v.jwksURL)
	if err != nil {
		return "", fmt.Errorf("get jwks: %w", err)
	}

	// 署名・exp・iss を検証
	tok, err := jwt.Parse([]byte(token),
		jwt.WithKeySet(keys),
		jwt.WithValidate(true),
		jwt.WithIssuer(v.issuer),
	)
	if err != nil {
		return "", fmt.Errorf("parse token: %w", err)
	}

	// Cognito のアクセストークンは aud ではなく client_id / token_use で確認する
	if tu, _ := tok.Get("token_use"); tu != "access" {
		return "", errors.New("token_use must be access")
	}
	if cid, _ := tok.Get("client_id"); cid != v.clientID {
		return "", errors.New("client_id mismatch")
	}
	if tok.Subject() == "" {
		return "", errors.New("sub is empty")
	}
	return tok.Subject(), nil
}

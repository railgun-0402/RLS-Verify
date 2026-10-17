#!/usr/bin/env bash
# 認証(Cognito) と 所属(memberships) と RLS の違いを体験するシナリオ
#
# ローカル(AUTH_MODE=dev): そのまま実行
# Cognito: TOKEN_A / TOKEN_C にアクセストークンを export してから実行
set -u

BASE=${BASE_URL:-http://localhost:8080}
ORG_A=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
ORG_B=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
TOKEN_A=${TOKEN_A:-dev:dev-user-a}   # 大学Aに所属
TOKEN_C=${TOKEN_C:-dev:dev-user-c}   # 認証はできるが、どこにも所属していない

call() { # title method path token org [body]
  echo
  echo "### $1"
  local args=(-s -w '\nHTTP %{http_code}\n' -X "$2" "$BASE$3"
              -H "Authorization: Bearer $4" -H "X-Organization-Id: $5")
  if [ -n "${6:-}" ]; then
    args+=(-H 'Content-Type: application/json' -d "$6")
  fi
  curl "${args[@]}"
}

call "1. user-a が大学Aを見る → 200・大学Aの行のみ" \
  GET /v1/donations "$TOKEN_A" "$ORG_A"

call "2. user-a が大学Bを指定 → 403（アプリの所属チェックで拒否）" \
  GET /v1/donations "$TOKEN_A" "$ORG_B"

call "3. user-c（Cognito 認証OK・所属なし）が大学Aを指定 → 403" \
  GET /v1/donations "$TOKEN_C" "$ORG_A"

call "4. 所属チェックを書き忘れた API で user-a が大学Bを指定" \
  GET /v1/unsafe/donations "$TOKEN_A" "$ORG_B"
echo "   → org_only ポリシー: 大学Bのデータが見える（漏洩）"
echo "   → with_membership ポリシー: 0件（DB が止める）"

call "5. ヘッダーは大学A・ボディで大学Bの寄付を登録 → 403（WITH CHECK 違反）" \
  POST /v1/donations "$TOKEN_A" "$ORG_A" \
  "{\"donor_name\":\"侵入者\",\"amount\":1,\"organization_id\":\"$ORG_B\"}"

call "6. 全国ランキング → 集計値だけ取れる" \
  GET /v1/ranking "$TOKEN_A" "$ORG_A"

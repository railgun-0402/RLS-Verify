-- ========== クロステナント集計（全国ランキング） ==========
-- 方針: app_user に全件 SELECT を許すのではなく、
--       「集計結果だけを返す関数」を実行する権限だけを渡す。
--
-- SECURITY DEFINER 関数は「所有者の権限」で実行される。
-- 所有者を ranking_reader（全件読めるポリシーを持つ、ログイン不可ロール）にすることで、
-- app_user は生データには触れず、集計値だけを受け取れる。

CREATE SCHEMA reporting;
GRANT USAGE ON SCHEMA reporting TO app_user, ranking_reader;
-- 関数の所有者になるロールはスキーマへの CREATE 権限が必要
GRANT CREATE ON SCHEMA reporting TO ranking_reader;

CREATE FUNCTION reporting.national_ranking()
RETURNS TABLE (organization_name text, total_amount bigint, donation_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = ''   -- SECURITY DEFINER では search_path を固定する（乗っ取り対策）
AS $$
  SELECT o.name,
         COALESCE(SUM(d.amount), 0)::bigint,
         COUNT(d.id)
  FROM public.organizations o
  LEFT JOIN public.donations d ON d.organization_id = o.id
  GROUP BY o.name
  ORDER BY 2 DESC
$$;

REVOKE ALL ON FUNCTION reporting.national_ranking() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reporting.national_ranking() TO app_user;

-- 所有者を ranking_reader に移す（そのロールへの SET 権限が必要）
GRANT ranking_reader TO CURRENT_USER;
ALTER FUNCTION reporting.national_ranking() OWNER TO ranking_reader;

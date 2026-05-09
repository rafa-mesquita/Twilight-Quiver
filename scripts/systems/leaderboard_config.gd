class_name LeaderboardConfig
extends RefCounted

# Credenciais do Supabase. Substitua pelos valores do seu projeto:
# Supabase Dashboard → Settings → API.
#
# A anon key é pública por design — segura pra commitar desde que as RLS policies
# (em supabase_schema.sql) só permitam INSERT/SELECT pra role anon.
const SUPABASE_URL: String = "https://gpltkmlapjhcheenfaxv.supabase.co"
const SUPABASE_ANON_KEY: String = "sb_publishable_mcqIYGsgE8I0AyzU4vW3JQ_SYgwYa4p"

# Endpoint da tabela runs (REST API auto-gerada do Supabase, formato PostgREST).
const RUNS_ENDPOINT: String = "/rest/v1/runs"


static func is_configured() -> bool:
	return not SUPABASE_URL.begins_with("https://YOUR-") \
		and not SUPABASE_ANON_KEY.begins_with("YOUR_")

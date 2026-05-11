class_name ApiConfig
extends RefCounted

# Configuração do backend custom do Twilight Quiver (limao studios).
# Endpoints: /runs (leaderboard) e /events (telemetria).

const API_BASE_URL: String = "https://twilight.hotsed.com"

# Chave pública embutida no jogo — não é segredo, serve só pra rate-limit /
# identificação. Substitua pelo valor real quando o servidor exigir.
const API_KEY: String = "wza5IedBNiVyjE6fc8dtagUSJUJrr0KSRZ2YNfXfA54"

# Endpoints (paths relativos à base URL).
const RUNS_ENDPOINT: String = "/api/runs"
const RUNS_VERSIONS_ENDPOINT: String = "/api/runs/versions"
const EVENTS_ENDPOINT: String = "/api/events"


static func is_configured() -> bool:
	return not API_BASE_URL.is_empty() and not API_BASE_URL.begins_with("https://YOUR-")


static func build_headers(include_content_type: bool = false) -> PackedStringArray:
	var h: PackedStringArray = ["X-API-Key: " + API_KEY]
	if include_content_type:
		h.append("Content-Type: application/json")
	return h

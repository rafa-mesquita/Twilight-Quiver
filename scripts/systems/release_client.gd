class_name ReleaseClient
extends Node

# Cliente HTTP pra API pública de releases (twilight.hotsed.com/api/releases).
# Uso típico: chama fetch_latest() no main_menu pra puxar a release mais nova
# e mostrar modal de patch notes uma vez por versão por usuário.

signal latest_fetched(release: Dictionary)  # Dict vazio = falha silenciosa
signal fetch_failed(message: String)

const _CONFIG := preload("res://scripts/systems/api_config.gd")

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_response)


func fetch_latest() -> void:
	if not _CONFIG.is_configured():
		latest_fetched.emit({})
		return
	var url: String = _CONFIG.API_BASE_URL + _CONFIG.RELEASES_ENDPOINT
	var headers: PackedStringArray = _CONFIG.build_headers()
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		fetch_failed.emit("Request error: " + str(err))
		latest_fetched.emit({})


func _on_response(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		fetch_failed.emit("HTTP %d" % code)
		latest_fetched.emit({})
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var releases: Array = []
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("releases"):
		releases = parsed["releases"]
	elif typeof(parsed) == TYPE_ARRAY:
		releases = parsed
	# Acha a marcada como is_latest=true; fallback pra primeira da lista.
	var latest: Dictionary = {}
	for r in releases:
		if typeof(r) == TYPE_DICTIONARY and bool(r.get("is_latest", false)):
			latest = r
			break
	if latest.is_empty() and not releases.is_empty() and typeof(releases[0]) == TYPE_DICTIONARY:
		latest = releases[0]
	latest_fetched.emit(latest)

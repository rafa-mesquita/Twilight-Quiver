class_name ReleaseClient
extends Node

# Cliente HTTP pras patch notes. Fonte = GitHub Releases do repo público de
# distribuição (twilight-quiver-releases), que o deploy popula automaticamente
# com as notas de cada versão. Antes usava o backend custom (twilight.hotsed.com
# /api/releases), mas ele ficava desatualizado e marcava is_latest numa entrada
# "LAUNCHER" sem notas → o modal nunca aparecia. O GitHub é sempre a versão real.
#
# Uso: main_menu chama fetch_latest() e mostra o modal uma vez por versão.

signal latest_fetched(release: Dictionary)  # {version, notes}; vazio = falha silenciosa
signal fetch_failed(message: String)

# Release pública mais nova (exclui draft/prerelease). Retorna tag_name + body.
const GITHUB_LATEST_URL: String = "https://api.github.com/repos/rafa-mesquita/twilight-quiver-releases/releases/latest"

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_response)


func fetch_latest() -> void:
	# GitHub exige User-Agent; sem ele responde 403.
	var headers: PackedStringArray = [
		"User-Agent: TwilightQuiver",
		"Accept: application/vnd.github+json",
	]
	print("[release-notes] GET ", GITHUB_LATEST_URL)
	var err: Error = _http.request(GITHUB_LATEST_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		print("[release-notes] HTTPRequest.request() error: ", err)
		fetch_failed.emit("Request error: " + str(err))
		latest_fetched.emit({})


func _on_response(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	print("[release-notes] response result=", result, " code=", code, " body_len=", body.size())
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		fetch_failed.emit("HTTP %d" % code)
		latest_fetched.emit({})
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		print("[release-notes] resposta inesperada (não-objeto)")
		latest_fetched.emit({})
		return
	# GitHub release: tag_name = versão, body = notas (markdown).
	var version: String = String(parsed.get("tag_name", ""))
	var notes: String = String(parsed.get("body", ""))
	print("[release-notes] latest version=", version, " notes_len=", notes.length())
	if version.is_empty():
		latest_fetched.emit({})
		return
	latest_fetched.emit({"version": version, "notes": notes})

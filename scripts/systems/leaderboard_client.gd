class_name LeaderboardClient
extends Node

# Cliente HTTP pro leaderboard no Supabase. Cria um HTTPRequest filho e expõe
# três operações: submit_run() pra enviar score, fetch_top() pra ler ranking
# (com filtro opcional por versão), fetch_versions() pra listar versões distintas.
#
# Requests são enfileiradas — HTTPRequest do Godot só processa uma de cada vez,
# então chamar submit/fetch em sequência sem aguardar dá ERR_BUSY no segundo.
# A fila garante que cada uma roda quando a anterior termina.
#
# Uso:
#   client.submit_run({"nickname": "rafa", "wave": 5, ...})
#   client.fetch_top(20)                       # todas as versões
#   client.fetch_top(20, "pre-alpha-0.0.1")    # filtrado por versão
#   client.fetch_versions()                    # lista pra popular dropdown

signal upload_succeeded()
signal upload_failed(message: String)
signal fetch_succeeded(rows: Array)
signal fetch_failed(message: String)
signal versions_fetched(versions: Array)
signal versions_fetch_failed(message: String)

const _CONFIG := preload("res://scripts/systems/leaderboard_config.gd")

enum _Op { UPLOAD, FETCH, FETCH_VERSIONS }

var _http: HTTPRequest
var _queue: Array = []
var _busy: bool = false
var _current_op: int = -1


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func submit_run(payload: Dictionary) -> void:
	if not _CONFIG.is_configured():
		upload_failed.emit("Leaderboard nao configurado")
		return
	var headers: PackedStringArray = _build_headers()
	headers.append("Content-Type: application/json")
	headers.append("Prefer: return=minimal")
	_enqueue({
		"op": _Op.UPLOAD,
		"url": _CONFIG.SUPABASE_URL + _CONFIG.RUNS_ENDPOINT,
		"headers": headers,
		"method": HTTPClient.METHOD_POST,
		"body": JSON.stringify(payload),
	})


func fetch_top(limit: int = 20, version_filter: String = "") -> void:
	if not _CONFIG.is_configured():
		fetch_failed.emit("Leaderboard nao configurado")
		return
	var url: String = "%s%s?order=score.desc&limit=%d" % [
		_CONFIG.SUPABASE_URL, _CONFIG.RUNS_ENDPOINT, limit
	]
	if not version_filter.is_empty():
		url += "&version=eq.%s" % version_filter.uri_encode()
	_enqueue({
		"op": _Op.FETCH,
		"url": url,
		"headers": _build_headers(),
		"method": HTTPClient.METHOD_GET,
		"body": "",
	})


func fetch_versions() -> void:
	if not _CONFIG.is_configured():
		versions_fetch_failed.emit("Leaderboard nao configurado")
		return
	# PostgREST não tem DISTINCT — pega só o campo version e dedupe client-side.
	var url: String = "%s%s?select=version&order=version.desc&limit=1000" % [
		_CONFIG.SUPABASE_URL, _CONFIG.RUNS_ENDPOINT
	]
	_enqueue({
		"op": _Op.FETCH_VERSIONS,
		"url": url,
		"headers": _build_headers(),
		"method": HTTPClient.METHOD_GET,
		"body": "",
	})


func _enqueue(req: Dictionary) -> void:
	_queue.append(req)
	_process_queue()


func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return
	var req: Dictionary = _queue.pop_front()
	_busy = true
	_current_op = req.op
	var err: Error = _http.request(req.url, req.headers, req.method, req.body)
	if err != OK:
		_busy = false
		_current_op = -1
		_emit_failure(req.op, "Erro iniciando request: %d" % int(err))
		_process_queue()


func _build_headers() -> PackedStringArray:
	return [
		"apikey: " + _CONFIG.SUPABASE_ANON_KEY,
		"Authorization: Bearer " + _CONFIG.SUPABASE_ANON_KEY,
	]


func _emit_failure(op: int, message: String) -> void:
	match op:
		_Op.UPLOAD: upload_failed.emit(message)
		_Op.FETCH:  fetch_failed.emit(message)
		_Op.FETCH_VERSIONS: versions_fetch_failed.emit(message)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var op: int = _current_op
	_busy = false
	_current_op = -1
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_failure(op, "Falha de rede (codigo %d)" % result)
		_process_queue()
		return
	var ok: bool = response_code >= 200 and response_code < 300
	var body_str: String = body.get_string_from_utf8()
	match op:
		_Op.UPLOAD:
			if ok:
				upload_succeeded.emit()
			else:
				upload_failed.emit("HTTP %d: %s" % [response_code, body_str])
		_Op.FETCH:
			if not ok:
				fetch_failed.emit("HTTP %d: %s" % [response_code, body_str])
			else:
				var parsed: Variant = JSON.parse_string(body_str)
				if typeof(parsed) != TYPE_ARRAY:
					fetch_failed.emit("Resposta invalida do servidor")
				else:
					fetch_succeeded.emit(parsed)
		_Op.FETCH_VERSIONS:
			if not ok:
				versions_fetch_failed.emit("HTTP %d: %s" % [response_code, body_str])
			else:
				var parsed_v: Variant = JSON.parse_string(body_str)
				if typeof(parsed_v) != TYPE_ARRAY:
					versions_fetch_failed.emit("Resposta invalida do servidor")
				else:
					# Dedupe client-side preservando ordem (mais novas primeiro).
					var seen: Dictionary = {}
					var unique: Array = []
					for row in parsed_v:
						if typeof(row) != TYPE_DICTIONARY:
							continue
						var v: String = str(row.get("version", ""))
						if v.is_empty() or seen.has(v):
							continue
						seen[v] = true
						unique.append(v)
					versions_fetched.emit(unique)
	_process_queue()

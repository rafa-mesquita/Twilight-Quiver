class_name LeaderboardClient
extends Node

# Cliente HTTP pro leaderboard custom (twilight.limaostudios.com.br).
# Três operações: submit_run() pra enviar score, fetch_top() pra ler ranking
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

const _CONFIG := preload("res://scripts/systems/api_config.gd")

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
		upload_failed.emit("API nao configurada")
		return
	_enqueue({
		"op": _Op.UPLOAD,
		"url": _CONFIG.API_BASE_URL + _CONFIG.RUNS_ENDPOINT,
		"headers": _CONFIG.build_headers(true),
		"method": HTTPClient.METHOD_POST,
		"body": JSON.stringify(payload),
	})


func fetch_top(limit: int = 20, version_filter: String = "") -> void:
	if not _CONFIG.is_configured():
		fetch_failed.emit("API nao configurada")
		return
	var url: String = "%s%s?limit=%d" % [_CONFIG.API_BASE_URL, _CONFIG.RUNS_ENDPOINT, limit]
	if not version_filter.is_empty():
		url += "&version=%s" % version_filter.uri_encode()
	_enqueue({
		"op": _Op.FETCH,
		"url": url,
		"headers": _CONFIG.build_headers(),
		"method": HTTPClient.METHOD_GET,
		"body": "",
	})


func fetch_versions() -> void:
	if not _CONFIG.is_configured():
		versions_fetch_failed.emit("API nao configurada")
		return
	_enqueue({
		"op": _Op.FETCH_VERSIONS,
		"url": _CONFIG.API_BASE_URL + _CONFIG.RUNS_VERSIONS_ENDPOINT,
		"headers": _CONFIG.build_headers(),
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
	print("[leaderboard] %s %s" % [_method_name(req.method), req.url])
	if req.body != "":
		print("[leaderboard] payload: ", req.body)
	var err: Error = _http.request(req.url, req.headers, req.method, req.body)
	if err != OK:
		_busy = false
		_current_op = -1
		_emit_failure(req.op, "Erro iniciando request: %d" % int(err))
		_process_queue()


func _method_name(m: int) -> String:
	match m:
		HTTPClient.METHOD_GET: return "GET"
		HTTPClient.METHOD_POST: return "POST"
		_: return "M%d" % m


func _emit_failure(op: int, message: String) -> void:
	match op:
		_Op.UPLOAD: upload_failed.emit(message)
		_Op.FETCH:  fetch_failed.emit(message)
		_Op.FETCH_VERSIONS: versions_fetch_failed.emit(message)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var op: int = _current_op
	_busy = false
	_current_op = -1
	var body_str_full: String = body.get_string_from_utf8()
	var body_preview: String = body_str_full if body_str_full.length() < 300 else body_str_full.substr(0, 300) + "..."
	print("[leaderboard] response result=%d code=%d body=%s" % [result, response_code, body_preview])
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_failure(op, "Falha de rede (codigo %d)" % result)
		_process_queue()
		return
	var ok: bool = response_code >= 200 and response_code < 300
	var body_str: String = body_str_full
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
				# Espera-se { "versions": [...] }. Aceita também array direto.
				var versions: Array = []
				if typeof(parsed_v) == TYPE_DICTIONARY and parsed_v.has("versions"):
					versions = parsed_v["versions"]
				elif typeof(parsed_v) == TYPE_ARRAY:
					versions = parsed_v
				else:
					versions_fetch_failed.emit("Resposta invalida do servidor")
					_process_queue()
					return
				versions_fetched.emit(versions)
	_process_queue()

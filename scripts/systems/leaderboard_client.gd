class_name LeaderboardClient
extends Node

# Cliente HTTP pro leaderboard no Supabase. Cria um HTTPRequest filho e expõe
# duas operações: submit_run() pra enviar score, fetch_top() pra ler ranking.
#
# Uso (envio):
#   client.upload_succeeded.connect(_on_ok)
#   client.upload_failed.connect(_on_err)
#   client.submit_run({"nickname": "rafa", "wave": 5, ...})
#
# Uso (leitura):
#   client.fetch_succeeded.connect(_on_rows)
#   client.fetch_failed.connect(_on_err)
#   client.fetch_top(20)

signal upload_succeeded()
signal upload_failed(message: String)
signal fetch_succeeded(rows: Array)
signal fetch_failed(message: String)

const _CONFIG := preload("res://scripts/systems/leaderboard_config.gd")

enum _Op { NONE, UPLOAD, FETCH }

var _http: HTTPRequest
var _pending_op: _Op = _Op.NONE


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func submit_run(payload: Dictionary) -> void:
	if not _CONFIG.is_configured():
		upload_failed.emit("Leaderboard nao configurado")
		return
	var url: String = _CONFIG.SUPABASE_URL + _CONFIG.RUNS_ENDPOINT
	var headers: PackedStringArray = _build_headers()
	headers.append("Content-Type: application/json")
	headers.append("Prefer: return=minimal")
	_pending_op = _Op.UPLOAD
	var body: String = JSON.stringify(payload)
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending_op = _Op.NONE
		upload_failed.emit("Erro iniciando request: %d" % int(err))


func fetch_top(limit: int = 20) -> void:
	if not _CONFIG.is_configured():
		fetch_failed.emit("Leaderboard nao configurado")
		return
	# PostgREST: ordena por score desc (calculado em score_calc.gd no envio).
	var url: String = "%s%s?order=score.desc&limit=%d" % [
		_CONFIG.SUPABASE_URL, _CONFIG.RUNS_ENDPOINT, limit
	]
	_pending_op = _Op.FETCH
	var err: Error = _http.request(url, _build_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_pending_op = _Op.NONE
		fetch_failed.emit("Erro iniciando request: %d" % int(err))


func _build_headers() -> PackedStringArray:
	return [
		"apikey: " + _CONFIG.SUPABASE_ANON_KEY,
		"Authorization: Bearer " + _CONFIG.SUPABASE_ANON_KEY,
	]


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var op: _Op = _pending_op
	_pending_op = _Op.NONE
	if result != HTTPRequest.RESULT_SUCCESS:
		var net_msg := "Falha de rede (codigo %d)" % result
		match op:
			_Op.UPLOAD: upload_failed.emit(net_msg)
			_Op.FETCH:  fetch_failed.emit(net_msg)
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
				return
			var parsed: Variant = JSON.parse_string(body_str)
			if typeof(parsed) != TYPE_ARRAY:
				fetch_failed.emit("Resposta invalida do servidor")
				return
			fetch_succeeded.emit(parsed)

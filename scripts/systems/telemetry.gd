extends Node

# Telemetria anônima do Twilight Quiver. Autoload singleton — chame
# Telemetry.track(event_type, properties) de qualquer lugar.
#
# Identidade:
#  - device_id: UUID v4 gerado uma vez e persistido em user://device_id.
#    Anônimo, sem PII. Permite rastrear retenção/sessões sem identificar pessoa.
#  - session_id: UUID v4 regenerado a cada abertura do jogo.
#  - run_id: UUID v4 setado via start_run() quando uma nova run começa; null
#    em eventos fora de run (sessão, menu).
#
# Buffer:
#  - Eventos são acumulados em _buffer e flushados a cada FLUSH_INTERVAL ou
#    quando _buffer atinge FLUSH_BATCH_SIZE. Também flush em quit (best-effort).
#  - Falha de network: eventos são descartados (não persistimos local pra evitar
#    bloating). Telemetria é fire-and-forget — perda eventual é aceitável.
#
# Backend: extende o Supabase do leaderboard. Tabela `events` no mesmo projeto.

const _CONFIG := preload("res://scripts/systems/api_config.gd")
const _DEVICE_ID_PATH: String = "user://device_id"
const _FLUSH_INTERVAL: float = 10.0
const _FLUSH_BATCH_SIZE: int = 20

var _device_id: String = ""
var _session_id: String = ""
var _run_id: String = ""
var _version: String = ""
var _platform: String = ""
var _buffer: Array = []
var _http: HTTPRequest
var _busy: bool = false
var _flush_timer: float = 0.0
# Timestamp (Time.get_ticks_msec()) de quando o run_id atual começou. Usado
# pra calcular tempo decorrido em cada evento dentro da run.
var _run_started_msec: int = 0


func _ready() -> void:
	_device_id = _load_or_create_device_id()
	_session_id = _generate_uuid()
	_version = str(ProjectSettings.get_setting("application/config/version", ""))
	_platform = OS.get_name()
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	track("session_start", {
		"is_debug": OS.is_debug_build(),
		"locale": OS.get_locale_language(),
	})


func _process(delta: float) -> void:
	# Em debug não auto-envia — só flush manual via flush_now() (dev buttons
	# na tela de morte / ESC-out). Em release roda timer normal.
	if OS.is_debug_build():
		return
	_flush_timer += delta
	if _flush_timer >= _FLUSH_INTERVAL:
		_flush_timer = 0.0
		_flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Em debug não auto-envia ao fechar. Em release, manda session_end + flush.
		if OS.is_debug_build():
			return
		track("session_end", {})
		_flush()


func flush_now() -> void:
	# Flush manual — usado pelos dev buttons da tela de morte e pelo ESC-out.
	_flush()


# ---------- API pública ----------

func track(event_type: String, properties: Dictionary = {}) -> void:
	if not _CONFIG.is_configured():
		return
	# Injeta time_ms (ms decorridos desde start_run) automaticamente em eventos
	# dentro de run. Em eventos fora de run (session_start/end), não inclui.
	var props: Dictionary = properties.duplicate()
	if not _run_id.is_empty() and _run_started_msec > 0:
		if not props.has("time_ms"):
			props["time_ms"] = Time.get_ticks_msec() - _run_started_msec
	var event: Dictionary = {
		"device_id": _device_id,
		"session_id": _session_id,
		"event_type": event_type,
		"version": _version,
		"platform": _platform,
		"properties": props,
	}
	if not _run_id.is_empty():
		event["run_id"] = _run_id
	_buffer.append(event)
	if _buffer.size() >= _FLUSH_BATCH_SIZE:
		_flush()


func start_run() -> String:
	# Gera um novo run_id e timestamp inicial. Eventos disparados depois disso
	# (até end_run) recebem time_ms = ms decorridos desde aqui.
	_run_id = _generate_uuid()
	_run_started_msec = Time.get_ticks_msec()
	return _run_id


func end_run() -> void:
	_run_id = ""
	_run_started_msec = 0


func get_run_elapsed_ms() -> int:
	if _run_started_msec <= 0:
		return 0
	return Time.get_ticks_msec() - _run_started_msec


func get_device_id() -> String:
	return _device_id


func get_session_id() -> String:
	return _session_id


func get_run_id() -> String:
	return _run_id


# ---------- Internals ----------

func _flush() -> void:
	if _busy or _buffer.is_empty() or not _CONFIG.is_configured():
		return
	var batch: Array = _buffer
	_buffer = []
	var url: String = _CONFIG.API_BASE_URL + _CONFIG.EVENTS_ENDPOINT
	var headers: PackedStringArray = _CONFIG.build_headers(true)
	var body: String = JSON.stringify(batch)
	print("[telemetry] POST ", url, " | events=", batch.size())
	print("[telemetry] payload: ", body)
	_busy = true
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		print("[telemetry] REQUEST_ERROR code=", err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var body_str: String = body.get_string_from_utf8()
	var body_preview: String = body_str if body_str.length() < 400 else body_str.substr(0, 400) + "..."
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if ok:
		print("[telemetry] OK code=", response_code, " body=", body_preview)
	else:
		print("[telemetry] FAIL result=", result, " code=", response_code, " body=", body_preview)


func _load_or_create_device_id() -> String:
	if FileAccess.file_exists(_DEVICE_ID_PATH):
		var f: FileAccess = FileAccess.open(_DEVICE_ID_PATH, FileAccess.READ)
		if f != null:
			var id: String = f.get_as_text().strip_edges()
			f.close()
			if not id.is_empty():
				return id
	var new_id: String = _generate_uuid()
	var f2: FileAccess = FileAccess.open(_DEVICE_ID_PATH, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(new_id)
		f2.close()
	return new_id


func _generate_uuid() -> String:
	# UUID v4 com variants padronizados (xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx).
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bytes: PackedByteArray = PackedByteArray()
	for i in 16:
		bytes.append(rng.randi() & 0xFF)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex: String = ""
	for b in bytes:
		hex += "%02x" % b
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12)
	]

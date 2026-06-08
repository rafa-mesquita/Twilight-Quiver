class_name GifEncoder
extends RefCounted

# Encoder GIF89a puro em GDScript (0 dependencias). Godot 4 nao tem encoder de GIF
# nativo, entao montamos o arquivo na mao:
#   - Quantizacao: paleta GLOBAL unica de ate 256 cores por corte mediano (median
#     cut) sobre buckets RGB555 (32768). Frames opacos (sem cor transparente).
#   - Compressao: LZW variavel-bit (algoritmo do omggif), empacotado LSB-first em
#     sub-blocos de <=255 bytes.
#   - Loop infinito (Netscape 2.0 application extension).
#
# Uso: GifEncoder.encode_images_to_file(frames, delay_cs, "caminho/out.gif").
# delay_cs = centesimos de segundo por frame (ex.: 8 ≈ 12.5fps).
#
# PESADO em CPU (loops por pixel + LZW). Chamar fora do main thread (ver
# death_replay.gd) pra nao congelar a UI.

const _BITS: int = 5                       # RGB555
const _BUCKETS: int = 1 << (_BITS * 3)     # 32768
const _MAX_COLORS: int = 256


static func encode_images_to_file(frames: Array, delay_cs: int, path: String) -> bool:
	var imgs: Array = _normalize_frames(frames)
	if imgs.is_empty():
		return false
	var w: int = (imgs[0] as Image).get_width()
	var h: int = (imgs[0] as Image).get_height()

	# --- Pass 1: histograma de buckets RGB555 (so contagem; cor = centro do bucket) ---
	var counts := PackedInt32Array()
	counts.resize(_BUCKETS)
	for im in imgs:
		var data: PackedByteArray = (im as Image).get_data()
		var n: int = data.size()
		var i: int = 0
		while i < n:
			var key: int = ((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3)
			counts[key] += 1
			i += 4

	var pal_data: Dictionary = _build_palette(counts)
	var palette: PackedByteArray = pal_data["palette"]  # 768 bytes (256*3)
	var lut: PackedByteArray = pal_data["lut"]          # _BUCKETS -> indice de paleta

	# --- Monta o arquivo ---
	var out := PackedByteArray()
	out.append_array("GIF89a".to_ascii_buffer())
	# Logical Screen Descriptor
	_put_u16(out, w)
	_put_u16(out, h)
	out.append(0xF7)  # GCT presente, color res 7, GCT de 256 cores (size field 7)
	out.append(0x00)  # background color index
	out.append(0x00)  # pixel aspect ratio
	out.append_array(palette)
	# Netscape loop extension (loop infinito)
	out.append_array(PackedByteArray([0x21, 0xFF, 0x0B]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))

	var dcs: int = maxi(delay_cs, 2)
	for im in imgs:
		# Graphic Control Extension (delay por frame)
		out.append_array(PackedByteArray([0x21, 0xF9, 0x04, 0x00]))
		_put_u16(out, dcs)
		out.append_array(PackedByteArray([0x00, 0x00]))  # transparent idx + terminador
		# Image Descriptor
		out.append(0x2C)
		_put_u16(out, 0)
		_put_u16(out, 0)
		_put_u16(out, w)
		_put_u16(out, h)
		out.append(0x00)  # sem local color table
		# Indices da imagem (pixel -> indice de paleta via LUT do bucket)
		var data: PackedByteArray = (im as Image).get_data()
		var npx: int = w * h
		var indices := PackedByteArray()
		indices.resize(npx)
		var pi: int = 0
		var bi: int = 0
		var dn: int = data.size()
		while bi < dn:
			var key: int = ((data[bi] >> 3) << 10) | ((data[bi + 1] >> 3) << 5) | (data[bi + 2] >> 3)
			indices[pi] = lut[key]
			pi += 1
			bi += 4
		# LZW + sub-blocos
		out.append(0x08)  # min code size (paleta de 256)
		var lzw: PackedByteArray = _lzw_compress(indices, 8)
		var off: int = 0
		var total: int = lzw.size()
		while off < total:
			var chunk: int = mini(255, total - off)
			out.append(chunk)
			out.append_array(lzw.slice(off, off + chunk))
			off += chunk
		out.append(0x00)  # block terminator

	out.append(0x3B)  # trailer

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(out)
	f.close()
	return true


# Converte os frames pra Image RGBA8 do mesmo tamanho (o do 1o frame valido).
static func _normalize_frames(frames: Array) -> Array:
	var out: Array = []
	var w: int = 0
	var h: int = 0
	for f in frames:
		if not (f is Image) or (f as Image).is_empty():
			continue
		var im: Image = f as Image
		if im.get_format() != Image.FORMAT_RGBA8:
			im = im.duplicate()
			im.convert(Image.FORMAT_RGBA8)
		if w == 0:
			w = im.get_width()
			h = im.get_height()
		elif im.get_width() != w or im.get_height() != h:
			if im == f:
				im = im.duplicate()
			im.resize(w, h, Image.INTERPOLATE_NEAREST)
		out.append(im)
	return out


# ---------------- Quantizacao (median cut) ----------------

static func _put_u16(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)
	buf.append((v >> 8) & 0xFF)


# Cor central de um bucket RGB555 (cada canal: nivel*8 + 4).
static func _bucket_r(key: int) -> int:
	return (((key >> 10) & 0x1F) << 3) | 4

static func _bucket_g(key: int) -> int:
	return (((key >> 5) & 0x1F) << 3) | 4

static func _bucket_b(key: int) -> int:
	return ((key & 0x1F) << 3) | 4


# Constroi a paleta global (<=256) por corte mediano e a LUT bucket->indice.
static func _build_palette(counts: PackedInt32Array) -> Dictionary:
	# Buckets populados (cor = centro, peso = contagem).
	var keys := PackedInt32Array()
	for key in range(_BUCKETS):
		if counts[key] > 0:
			keys.append(key)
	var ncols: int = keys.size()

	var palette := PackedByteArray()
	palette.resize(_MAX_COLORS * 3)
	var lut := PackedByteArray()
	lut.resize(_BUCKETS)

	if ncols == 0:
		return {"palette": palette, "lut": lut}

	# `order` = indices em keys, reordenado conforme as caixas vao sendo cortadas.
	var order := PackedInt32Array()
	order.resize(ncols)
	for i in ncols:
		order[i] = i
	var boxes: Array = [{"lo": 0, "hi": ncols}]

	while boxes.size() < _MAX_COLORS:
		# Escolhe a caixa com maior amplitude de cor (e >1 cor) pra cortar.
		var target: int = -1
		var target_axis: int = 0
		var best_range: int = 0
		for bi in boxes.size():
			var box: Dictionary = boxes[bi]
			if box["hi"] - box["lo"] <= 1:
				continue
			var rng: Array = _box_ranges(order, keys, box["lo"], box["hi"])
			for axis in 3:
				if rng[axis] > best_range:
					best_range = rng[axis]
					target = bi
					target_axis = axis
		if target < 0:
			break  # nenhuma caixa cortavel
		_split_box(boxes, target, target_axis, order, keys, counts)

	# Cada caixa final vira 1 cor (media ponderada) e mapeia seus buckets pro indice.
	for bi in boxes.size():
		var box: Dictionary = boxes[bi]
		var tw: int = 0
		var ar: int = 0
		var ag: int = 0
		var ab: int = 0
		for oi in range(box["lo"], box["hi"]):
			var key: int = keys[order[oi]]
			var c: int = counts[key]
			tw += c
			ar += _bucket_r(key) * c
			ag += _bucket_g(key) * c
			ab += _bucket_b(key) * c
			lut[key] = bi
		if tw > 0:
			palette[bi * 3] = clampi(ar / tw, 0, 255)
			palette[bi * 3 + 1] = clampi(ag / tw, 0, 255)
			palette[bi * 3 + 2] = clampi(ab / tw, 0, 255)
	return {"palette": palette, "lut": lut}


# Amplitude (max-min) de cada canal numa faixa de `order`.
static func _box_ranges(order: PackedInt32Array, keys: PackedInt32Array, lo: int, hi: int) -> Array:
	var rmin := 255; var rmax := 0
	var gmin := 255; var gmax := 0
	var bmin := 255; var bmax := 0
	for oi in range(lo, hi):
		var key: int = keys[order[oi]]
		var r: int = _bucket_r(key)
		var g: int = _bucket_g(key)
		var b: int = _bucket_b(key)
		rmin = mini(rmin, r); rmax = maxi(rmax, r)
		gmin = mini(gmin, g); gmax = maxi(gmax, g)
		bmin = mini(bmin, b); bmax = maxi(bmax, b)
	return [rmax - rmin, gmax - gmin, bmax - bmin]


# Corta a caixa `target` no eixo dado: ordena a faixa por aquele canal e divide na
# mediana ponderada por contagem. Substitui a caixa por duas.
static func _split_box(boxes: Array, target: int, axis: int, order: PackedInt32Array, keys: PackedInt32Array, counts: PackedInt32Array) -> void:
	var box: Dictionary = boxes[target]
	var lo: int = box["lo"]
	var hi: int = box["hi"]
	# Extrai a faixa, ordena pelo canal `axis`, escreve de volta.
	var slice: Array = []
	for oi in range(lo, hi):
		slice.append(order[oi])
	slice.sort_custom(func(a, b): return _axis_val(keys[a], axis) < _axis_val(keys[b], axis))
	for i in slice.size():
		order[lo + i] = slice[i]
	# Mediana ponderada: acha onde a contagem acumulada cruza metade do total.
	var total: int = 0
	for oi in range(lo, hi):
		total += counts[keys[order[oi]]]
	var half: int = total / 2
	var acc: int = 0
	var mid: int = lo + 1
	for oi in range(lo, hi - 1):
		acc += counts[keys[order[oi]]]
		if acc >= half:
			mid = oi + 1
			break
	mid = clampi(mid, lo + 1, hi - 1)
	boxes[target] = {"lo": lo, "hi": mid}
	boxes.append({"lo": mid, "hi": hi})


static func _axis_val(key: int, axis: int) -> int:
	match axis:
		0: return _bucket_r(key)
		1: return _bucket_g(key)
		_: return _bucket_b(key)


# ---------------- LZW (GIF) ----------------

# Comprime os indices (1 byte/pixel) em bytes LZW crus. Algoritmo do omggif:
# emite `cur` ANTES de crescer o code_size / adicionar entrada; clear quando a
# tabela enche (4096). Empacota LSB-first.
static func _lzw_compress(indices: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var clear_code: int = 1 << min_code_size
	var end_code: int = clear_code + 1
	var code_size: int = min_code_size + 1
	var next_code: int = end_code + 1
	var dict: Dictionary = {}

	var bytes := PackedByteArray()
	var bit_buffer: int = 0
	var bit_count: int = 0

	# emite clear inicial
	bit_buffer |= clear_code << bit_count
	bit_count += code_size
	while bit_count >= 8:
		bytes.append(bit_buffer & 0xFF)
		bit_buffer >>= 8
		bit_count -= 8

	var n: int = indices.size()
	if n == 0:
		# fluxo vazio: so end code + flush
		bit_buffer |= end_code << bit_count
		bit_count += code_size
		while bit_count >= 8:
			bytes.append(bit_buffer & 0xFF)
			bit_buffer >>= 8
			bit_count -= 8
		if bit_count > 0:
			bytes.append(bit_buffer & 0xFF)
		return bytes

	var cur: int = indices[0]
	var idx: int = 1
	while idx < n:
		var k: int = indices[idx]
		idx += 1
		var key: int = (cur << 8) | k
		if dict.has(key):
			cur = dict[key]
		else:
			# emite cur no code_size atual
			bit_buffer |= cur << bit_count
			bit_count += code_size
			while bit_count >= 8:
				bytes.append(bit_buffer & 0xFF)
				bit_buffer >>= 8
				bit_count -= 8
			if next_code == 4096:
				# tabela cheia: emite clear e reseta
				bit_buffer |= clear_code << bit_count
				bit_count += code_size
				while bit_count >= 8:
					bytes.append(bit_buffer & 0xFF)
					bit_buffer >>= 8
					bit_count -= 8
				dict.clear()
				code_size = min_code_size + 1
				next_code = end_code + 1
			else:
				if next_code >= (1 << code_size) and code_size < 12:
					code_size += 1
				dict[key] = next_code
				next_code += 1
			cur = k

	# emite ultimo cur
	bit_buffer |= cur << bit_count
	bit_count += code_size
	while bit_count >= 8:
		bytes.append(bit_buffer & 0xFF)
		bit_buffer >>= 8
		bit_count -= 8
	# end code
	bit_buffer |= end_code << bit_count
	bit_count += code_size
	while bit_count >= 8:
		bytes.append(bit_buffer & 0xFF)
		bit_buffer >>= 8
		bit_count -= 8
	# flush dos bits restantes
	if bit_count > 0:
		bytes.append(bit_buffer & 0xFF)
	return bytes

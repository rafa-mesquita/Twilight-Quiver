#!/usr/bin/env python3
"""Decoder minimo de .aseprite -> PNG.

Suporta o caso comum dos icones do projeto: frame 0, color depth 32bpp (RGBA)
ou 8bpp (indexed c/ palette), cels comprimidos por zlib (cel type 2) ou raw
(cel type 0). Compoe todas as camadas do frame 0 por ordem de layer index com
alpha-blend normal. Uso:

    python aseprite_to_png.py entrada.aseprite saida.png
"""
import struct
import sys
import zlib
from PIL import Image


def _alpha_over(dst, src):
    """Alpha-composita src sobre dst (ambos RGBA tuplas de bytes em lista)."""
    sr, sg, sb, sa = src
    if sa == 0:
        return dst
    if sa == 255:
        return src
    dr, dg, db, da = dst
    a = sa / 255.0
    inv = 1.0 - a
    out_a = sa + int(da * inv)
    if out_a == 0:
        return (0, 0, 0, 0)
    nr = int((sr * a + dr * (da / 255.0) * inv))
    ng = int((sg * a + dg * (da / 255.0) * inv))
    nb = int((sb * a + db * (da / 255.0) * inv))
    return (min(nr, 255), min(ng, 255), min(nb, 255), min(out_a, 255))


def decode(path):
    with open(path, "rb") as f:
        data = f.read()

    # --- Header (128 bytes) ---
    (file_size, magic, frames, width, height, depth) = struct.unpack_from("<IHHHHH", data, 0)
    if magic != 0xA5E0:
        raise ValueError(f"magic invalido: {magic:#06x}")
    # paleta (color depth 8) acumulada dos chunks
    palette = {}  # index -> (r,g,b,a)
    transparent_index = data[28]

    canvas = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]

    off = 128
    # Le apenas o frame 0 (icones sao estaticos). Itera chunks do frame 0.
    frame_bytes, fmagic, old_chunks, _dur, new_chunks = struct.unpack_from("<IHHHxxI", data, off)
    if fmagic != 0xF1FA:
        raise ValueError(f"frame magic invalido: {fmagic:#06x}")
    n_chunks = new_chunks if new_chunks != 0 else old_chunks
    p = off + 16

    cels = []  # (layer_index, x, y, w, h, pixels[list de (r,g,b,a)])
    layer_visible = []  # paralelo ao layer index: True se deve compor essa layer
    for _ in range(n_chunks):
        chunk_size, chunk_type = struct.unpack_from("<IH", data, p)
        cdata = data[p + 6: p + chunk_size]
        if chunk_type == 0x2004:  # layer
            lflags = struct.unpack_from("<H", cdata, 0)[0]
            # bit 0 = visivel; bit 6 (64) = reference layer (so guia do artista).
            visible = bool(lflags & 1) and not bool(lflags & 64)
            layer_visible.append(visible)
        elif chunk_type == 0x2019:  # palette (novo)
            new_size, first, last = struct.unpack_from("<III", cdata, 0)
            q = 12 + 8  # pula reserved[8]
            idx = first
            while idx <= last:
                flags, r, g, b, a = struct.unpack_from("<HBBBB", cdata, q)
                q += 6
                if flags & 1:  # tem nome
                    nlen = struct.unpack_from("<H", cdata, q)[0]
                    q += 2 + nlen
                palette[idx] = (r, g, b, a)
                idx += 1
        elif chunk_type == 0x0004 or chunk_type == 0x0011:  # palette antiga
            npackets = struct.unpack_from("<H", cdata, 0)[0]
            q = 2
            idx = 0
            for _pk in range(npackets):
                skip = cdata[q]; ncol = cdata[q + 1]; q += 2
                idx += skip
                cnt = ncol if ncol != 0 else 256
                for _c in range(cnt):
                    r, g, b = cdata[q], cdata[q + 1], cdata[q + 2]; q += 3
                    palette[idx] = (r, g, b, 255)
                    idx += 1
        elif chunk_type == 0x2005:  # cel
            layer_index, x, y, opacity, cel_type = struct.unpack_from("<HhhBH", cdata, 0)
            # Pula cels de layers invisiveis / reference (guias do artista).
            if layer_index < len(layer_visible) and not layer_visible[layer_index]:
                p += chunk_size
                continue
            # 7 bytes reservados (ou z-index+reserved) apos cel_type
            body = cdata[9 + 7:]
            if cel_type in (0, 2):
                cw, ch = struct.unpack_from("<HH", body, 0)
                raw = body[4:]
                if cel_type == 2:
                    raw = zlib.decompress(raw)
                pixels = _raw_to_rgba(raw, cw, ch, depth, palette, transparent_index)
                cels.append((layer_index, x, y, cw, ch, pixels))
            # cel_type 1 (linked) ignorado: frame 0 nao costuma linkar
        p += chunk_size

    # Compoe por ordem de layer index
    cels.sort(key=lambda c: c[0])
    for (_li, x, y, cw, ch, pixels) in cels:
        for j in range(ch):
            cy = y + j
            if cy < 0 or cy >= height:
                continue
            for i in range(cw):
                cx = x + i
                if cx < 0 or cx >= width:
                    continue
                canvas[cy][cx] = _alpha_over(canvas[cy][cx], pixels[j * cw + i])

    img = Image.new("RGBA", (width, height))
    flat = []
    for row in canvas:
        flat.extend(row)
    img.putdata(flat)
    return img


def _raw_to_rgba(raw, w, h, depth, palette, transparent_index):
    out = []
    if depth == 32:
        for i in range(w * h):
            r, g, b, a = raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]
            out.append((r, g, b, a))
    elif depth == 16:  # grayscale + alpha
        for i in range(w * h):
            v, a = raw[i * 2], raw[i * 2 + 1]
            out.append((v, v, v, a))
    elif depth == 8:  # indexed
        for i in range(w * h):
            idx = raw[i]
            if idx == transparent_index:
                out.append((0, 0, 0, 0))
            else:
                out.append(palette.get(idx, (0, 0, 0, 0)))
    else:
        raise ValueError(f"depth nao suportado: {depth}")
    return out


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    image = decode(src)
    image.save(dst)
    print(f"OK {src} -> {dst} ({image.width}x{image.height})")

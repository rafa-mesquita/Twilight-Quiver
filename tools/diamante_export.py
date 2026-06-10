#!/usr/bin/env python3
"""Exporta do Diamante de primeira classe.aseprite:
  1) icone completo (todas as camadas)         -> diamante_primeira_classe.png
  2) so a camada 'item' + brilho branco (broche) -> diamante_broche.png

Reusa o parsing do aseprite_to_png mas mantem as camadas separadas (por nome).
"""
import struct
import sys
import zlib
from PIL import Image, ImageFilter

ASE = "assets/Hud/itens/Diamante de primeira classe.aseprite"
OUT_ICON = "assets/Hud/itens/diamante_primeira_classe.png"
OUT_BROCHE = "assets/Hud/itens/diamante_broche.png"


def _raw_to_rgba(raw, w, h, depth):
    out = []
    if depth == 32:
        for i in range(w * h):
            out.append((raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]))
    else:
        raise ValueError(f"depth nao suportado: {depth}")
    return out


def parse_layers(path):
    with open(path, "rb") as f:
        data = f.read()
    (_fs, magic, _frames, width, height, depth) = struct.unpack_from("<IHHHHH", data, 0)
    if magic != 0xA5E0:
        raise ValueError("magic invalido")
    off = 128
    _fb, fmagic, old_chunks, _dur, new_chunks = struct.unpack_from("<IHHHxxI", data, off)
    n_chunks = new_chunks if new_chunks != 0 else old_chunks
    p = off + 16
    names = []      # layer_index -> name
    layers = {}     # name -> PIL.Image (canvas size)
    for _ in range(n_chunks):
        chunk_size, chunk_type = struct.unpack_from("<IH", data, p)
        cdata = data[p + 6: p + chunk_size]
        if chunk_type == 0x2004:  # layer
            nlen = struct.unpack_from("<H", cdata, 16)[0]
            names.append(cdata[18:18 + nlen].decode("utf-8", "replace"))
        elif chunk_type == 0x2005:  # cel
            li, x, y, _op, cel_type = struct.unpack_from("<HhhBH", cdata, 0)
            body = cdata[9 + 7:]
            if cel_type in (0, 2):
                cw, ch = struct.unpack_from("<HH", body, 0)
                raw = body[4:]
                if cel_type == 2:
                    raw = zlib.decompress(raw)
                px = _raw_to_rgba(raw, cw, ch, depth)
                img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
                cel = Image.new("RGBA", (cw, ch))
                cel.putdata(px)
                img.alpha_composite(cel, (x, y))
                layers[names[li]] = img
        p += chunk_size
    return width, height, names, layers


def make_broche(item_img):
    """item_img: camada 'item' no canvas cheio. Corta no bbox e adiciona brilho branco."""
    bbox = item_img.getbbox()
    item = item_img.crop(bbox)
    iw, ih = item.size
    pad = 7
    W, H = iw + 2 * pad, ih + 2 * pad
    # Silhueta dilatada do alpha pra formar o halo.
    alpha = item.getchannel("A")
    dil = alpha.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MaxFilter(3))
    big = Image.new("L", (W, H), 0)
    big.paste(dil, (pad, pad))
    big = big.filter(ImageFilter.GaussianBlur(2.2))
    # Reforca o nucleo do brilho (alpha um pouco mais forte perto do broche).
    big = big.point(lambda a: min(255, int(a * 1.6)))
    glow = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    glow.putalpha(big)
    glow_rgb = Image.merge("RGBA", (
        Image.new("L", (W, H), 255), Image.new("L", (W, H), 255),
        Image.new("L", (W, H), 255), big))
    out = glow_rgb.copy()
    out.alpha_composite(item, (pad, pad))
    return out


def main():
    width, height, names, layers = parse_layers(ASE)
    # 1) Icone completo: compoe todas as camadas por ordem de index.
    icon = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for nm in names:
        if nm in layers:
            icon.alpha_composite(layers[nm])
    icon.save(OUT_ICON)
    print(f"OK icone -> {OUT_ICON} ({icon.width}x{icon.height})")
    # 2) Broche: so a camada 'item' + brilho.
    if "item" not in layers:
        raise ValueError("camada 'item' nao encontrada: " + str(names))
    broche = make_broche(layers["item"])
    broche.save(OUT_BROCHE)
    print(f"OK broche -> {OUT_BROCHE} ({broche.width}x{broche.height})")


if __name__ == "__main__":
    main()

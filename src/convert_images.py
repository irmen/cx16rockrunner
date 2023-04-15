import os
import configparser
import glob
from dataclasses import dataclass
from typing import Tuple
from PIL import Image


def reduce_colorspace(palette: list[int]) -> list[int]:
    # convert to 4:4:4 RGB
    result = []
    for c in palette:
        c &= 0xf0
        result.append(c | (c >> 4))
    return result


def cvt(filename: str) -> Image.Image:
    img = Image.open(filename)
    pal = img.getpalette()  # note: color 0 is the transparency color (magenta)
    num_colors = len(pal) // 3
    assert num_colors <= 16
    width, height = img.size
    num_tiles = width // 16 * height // 16
    converted = Image.new('P', (num_tiles * 16, 16))
    converted.putpalette(reduce_colorspace(pal))
    converted.info['transparency'] = 0
    print(f"gathering '{filename}' : {num_colors} colors, {num_tiles} tiles")
    for tile_idx in range(num_tiles):
        sx = (tile_idx * 16) & (16 * 8 - 1)
        sy = (tile_idx // 8) * 16
        tile = img.crop((sx, sy, sx + 16, sy + 16))
        converted.paste(tile, (tile_idx * 16, 0))
    return converted


def combine_palettes(parts: list[Image.Image]) -> list[int]:
    palette = []
    for part in parts:
        pal = part.getpalette()
        pal += [0, 0, 0] * (16 - len(pal) // 3)
        assert len(pal) == 16 * 3
        palette += pal
    assert len(palette) <= 256 * 3
    return palette


def join_part_into_full(part: Image.Image, part_index: int, x_offset: int, converted: Image.Image) -> None:
    palette_offset = part_index * 16
    for y in range(16):
        for x in range(part.size[0]):
            color = part.getpixel((x, y))
            if color != 0:
                color += palette_offset
            converted.putpixel((x + x_offset, y), color)


@dataclass
class TilesPart:
    name: str
    tile_idx_offset: int
    palette_offset: int
    num_tiles: int
    image: Image.Image


def combine_parts() -> Tuple[Image.Image, int, list[TilesPart]]:
    total_tiles = 0
    palette_offset = 0
    parts = []
    for fn in sorted(glob.glob("images/bd_*.png")):
        part = cvt(fn)
        num_tiles = part.size[0] // 16
        parts.append(TilesPart(os.path.basename(fn), total_tiles, palette_offset, num_tiles, part))
        total_tiles += num_tiles
        palette_offset += 1
    for part in parts:
        print(
            f"{part.name} tile offset={part.tile_idx_offset} palette offset={part.palette_offset} ({part.num_tiles} tiles)")
    # we assume every palette differs from every other,
    # so every partial image gets its own 16 colors in the final palette
    # not all colors might be used though, but that can't be helped.
    x_offset = 0
    converted = Image.new('P', (total_tiles * 16, 16))
    converted.putpalette(combine_palettes([p.image for p in parts]))
    converted.info['transparency'] = 0
    for index, part in enumerate(parts):
        join_part_into_full(part.image, index, x_offset, converted)
        x_offset += part.image.size[0]
    return converted, total_tiles, parts


def convert_tiles() -> list[TilesPart]:
    converted, num_tiles, tiles_parts = combine_parts()
    print(f"converting {num_tiles} tiles to 4bpp tile data")
    palette = converted.getpalette()
    print("total number of palette entries allocated:", len(palette) // 3)
    data = bytearray()
    for tile_idx in range(num_tiles):
        for y in range(16):
            for x in range(0, 16, 2):
                color1 = converted.getpixel((x + tile_idx * 16, y)) & 15
                color2 = converted.getpixel((x + tile_idx * 16 + 1, y)) & 15
                data.append(color1 << 4 | color2)
    converted.save("converted.png")
    open("TILES.BIN", "wb").write(data)
    cx16palette = bytearray()
    for pi in range(0, len(palette), 3):
        r, g, b = palette[pi] >> 4, palette[pi + 1] >> 4, palette[pi + 2] >> 4
        cx16palette.append(g << 4 | b)
        cx16palette.append(r)
    cx16palette[0] = 0  # make first entry black
    cx16palette[1] = 0  # make first entry black
    open("TILES.PAL", "wb").write(cx16palette)
    return tiles_parts


def make_catalog(parts: list[TilesPart]) -> None:
    config = configparser.ConfigParser()
    config.read("images/catalog.ini")
    total_num_tiles = sum(part.num_tiles for part in parts)
    object_id = 0
    tile_idx = []
    palette_offsets = []
    num_anim_frames = []
    anim_fps = []
    rounded = []
    consumable = []
    explodable = []
    with open("src/objects.p8", "wt") as out:
        out.write("objects {\n")
        for part in parts:
            section = config[part.name]
            for offsets, tilename in section.items():
                out.write(f"    const ubyte {tilename} = {object_id}\n")
                palette_offsets.append(part.palette_offset)
                if '-' in offsets:
                    # it is an animation sequence
                    start, end = offsets.split('-')
                    start = int(start, 16)
                    end = int(end, 16)
                    tile_idx.append(start + part.tile_idx_offset)
                    num_anim_frames.append(end - start + 1)
                    anim_fps.append(1)  # TODO
                else:
                    # just 1 tile for this object
                    tilenum = int(offsets, 16)
                    tile_idx.append(tilenum + part.tile_idx_offset)
                    num_anim_frames.append(0)
                    anim_fps.append(0)
                object_id += 1
        assert len(tile_idx) == len(palette_offsets) == len(num_anim_frames) == len(anim_fps) == object_id
        out.write("\n")
        out.write(f"    const ubyte NUM_OBJECTS = {object_id}\n")
        tile_lo = [t & 255 for t in tile_idx]
        tile_hi = [t >> 8 for t in tile_idx]
        out.write(f"    ubyte[NUM_OBJECTS] @shared tile_lo = {tile_lo}\n")
        out.write(f"    ubyte[NUM_OBJECTS] @shared tile_hi = {tile_hi}\n")
        palette_offsets = [o << 4 for o in palette_offsets]
        out.write(f"    ubyte[NUM_OBJECTS] @shared palette_offsets_preshifted = {palette_offsets}\n")
        out.write(f"    ubyte[NUM_OBJECTS] @shared anim_frames = {num_anim_frames}\n")
        out.write(f"    ubyte[NUM_OBJECTS] @shared anim_fps    = {anim_fps}\n")
        out.write("}\n")


if __name__ == '__main__':
    tiles_parts = convert_tiles()
    make_catalog(tiles_parts)

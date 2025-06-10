import os
import configparser
from dataclasses import dataclass
from typing import Tuple
from PIL import Image
from cx16images import BitmapImage, flat_palette_to_vera, reduce_colorspace, flat_palette_to_rgb, rgb_palette_to_flat


@dataclass
class TilesPart:
    name: str
    tile_idx_offset: int
    palette_offset: int
    num_tiles: int
    image: Image.Image


class Converter:
    images_directory = "???"
    def __init__(self, images_directory: str):
        self.images_directory = images_directory


    def cvt(self, filename: str) -> Image.Image:
        img = Image.open(filename)
        pal = img.getpalette()  # note: color 0 is the transparency color (magenta)
        num_colors = len(pal) // 3
        assert num_colors <= 16
        width, height = img.size
        if (width % 16) != 0:
            raise ValueError("width is not a multiple of 16: " + str(filename))
        num_tiles = width // 16 * height // 16
        converted = Image.new('P', (num_tiles * 16, 16))
        rgb_pal = reduce_colorspace(flat_palette_to_rgb(pal))
        converted.putpalette(rgb_palette_to_flat(rgb_pal))
        converted.info['transparency'] = 0
        print(f"gathering '{filename}' : {num_colors} colors, {num_tiles} tiles")
        for tile_idx in range(num_tiles):
            sx = (tile_idx * 16) & (16 * 8 - 1)
            sy = (tile_idx // 8) * 16
            tile = img.crop((sx, sy, sx + 16, sy + 16))
            converted.paste(tile, (tile_idx * 16, 0))
        return converted


    def combine_palettes(self, parts: list[Image.Image]) -> list[int]:
        palette = []
        for part in parts:
            pal = part.getpalette()
            pal += [0, 0, 0] * (16 - len(pal) // 3)
            assert len(pal) == 16 * 3
            palette += pal
        assert len(palette) <= 256 * 3
        return palette


    def join_part_into_full(self, part: Image.Image, part_index: int, x_offset: int, converted: Image.Image) -> None:
        palette_offset = part_index * 16
        for y in range(16):
            for x in range(part.size[0]):
                color = part.getpixel((x, y))
                if color != 0:
                    color += palette_offset
                converted.putpixel((x + x_offset, y), color)


    def combine_parts(self) -> Tuple[Image.Image, int, list[TilesPart]]:
        total_tiles = 0
        palette_offset = 0
        parts = []
        config = configparser.ConfigParser()
        config.read(self.images_directory+"/catalog.ini")
        for fn in config.sections():
            part = self.cvt(self.images_directory + "/" + fn)
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
        converted.putpalette(self.combine_palettes([p.image for p in parts]))
        converted.info['transparency'] = 0
        for index, part in enumerate(parts):
            self.join_part_into_full(part.image, index, x_offset, converted)
            x_offset += part.image.size[0]
        return converted, total_tiles, parts


    def convert_tiles(self, filename_prefix: str) -> list[TilesPart]:
        converted, num_tiles, tiles_parts = self.combine_parts()
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
        open(filename_prefix+".BIN", "wb").write(data)
        cx16palette = flat_palette_to_vera(palette)
        # make first entry black:
        cx16palette[0] = 0
        cx16palette[1] = 0
        open(filename_prefix+".PAL", "wb").write(cx16palette)
        return tiles_parts


    def get_animspeed(self, attributes: set[str]) -> int:
        for attr in attributes:
            if attr.startswith('A'):
                return int(attr.split('=')[1])
        return 0


    def make_catalog(self, parts: list[TilesPart]) -> None:
        config = configparser.ConfigParser()
        config.read(self.images_directory + "/catalog.ini")
        object_id = 0
        tile_idx = []
        palette_offsets = []
        anim_sizes = []
        anim_speeds = []
        anim_looping = []
        rounded = []
        consumable = []
        explodable = []
        isrockford = []
        isfallable = []
        iseatable = []
        object_ids = {}
        with open("src/objects.p8", "wt") as out:
            out.write("; NOTE: this code is automatically generated. Do not edit!\n")
            out.write("objects {\n")
            for part in parts:
                section = config[part.name]
                for offsets, tilename in section.items():
                    tilename = tilename.strip()
                    if ' ' in tilename:
                        tilename, attributes = tilename.split(" ", maxsplit=1)
                        attributes = set(attributes.strip().split(','))
                    else:
                        attributes = set()
                    object_ids[tilename] = object_id
                    out.write(f"    const ubyte {tilename} = {object_id}\n")
                    palette_offsets.append(part.palette_offset)
                    if '-' in offsets:
                        # it is an animation sequence
                        speed = self.get_animspeed(attributes)
                        assert speed > 0
                        anim_speeds.append(speed)
                        start, end = offsets.split('-')
                        start = int(start, 16)
                        end = int(end, 16)
                        tile_idx.append(start + part.tile_idx_offset)
                        anim_sizes.append(end - start + 1)
                        anim_looping.append(False if 'O' in attributes else True)
                    else:
                        # just 1 tile for this object
                        speed = self.get_animspeed(attributes)
                        assert speed == 0
                        anim_speeds.append(0)
                        tilenum = int(offsets, 16)
                        tile_idx.append(tilenum + part.tile_idx_offset)
                        anim_sizes.append(0)
                        anim_looping.append(False)
                    object_id += 1
                    rounded.append("R" in attributes)
                    consumable.append("C" in attributes)
                    explodable.append("X" in attributes)
                    isrockford.append("P" in attributes)
                    isfallable.append("F" in attributes)
                    iseatable.append("E" in attributes)
            total_num_tiles = object_id
            assert len(tile_idx) == len(palette_offsets) == len(anim_sizes) == len(anim_speeds) == len(rounded) == \
                   len(anim_looping) == len(consumable) == len(explodable) == \
                   len(isrockford) == len(isfallable) == len(iseatable) == total_num_tiles
            attributes_flags = []
            for ix in range(total_num_tiles):
                attr_flag = ""
                if anim_looping[ix]:
                    attr_flag += "ATTRF_LOOPINGANIM|"
                if consumable[ix]:
                    attr_flag += "ATTRF_CONSUMABLE|"
                if rounded[ix]:
                    attr_flag += "ATTRF_ROUNDED|"
                if explodable[ix]:
                    attr_flag += "ATTRF_EXPLODABLE|"
                if isrockford[ix]:
                    attr_flag += "ATTRF_ROCKFORD|"
                if isfallable[ix]:
                    attr_flag += "ATTRF_FALLABLE|"
                if iseatable[ix]:
                    attr_flag += "ATTRF_EATABLE|"
                attributes_flags.append(attr_flag.strip('|') or "0")
            out.write("\n")
            out.write(f"    const ubyte NUM_OBJECTS = {total_num_tiles}\n")
            tile_lo = [t & 255 for t in tile_idx]
            tile_hi = [t >> 8 for t in tile_idx]
            out.write(f"    ubyte[NUM_OBJECTS] @shared tile_lo = {tile_lo}\n")
            out.write(f"    ubyte[NUM_OBJECTS] @shared tile_hi = {tile_hi}\n")
            palette_offsets = [o << 4 for o in palette_offsets]
            out.write(f"    ubyte[NUM_OBJECTS] @shared palette_offsets_preshifted = {palette_offsets}\n")
            out.write(f"    ubyte[NUM_OBJECTS] @shared anim_sizes = {anim_sizes}\n")
            out.write(f"    ubyte[NUM_OBJECTS] @shared anim_speeds = {anim_speeds}\n")
            out.write(f"    const ubyte ATTRF_CONSUMABLE       = %00000010\n")
            out.write(f"    const ubyte ATTRF_ROUNDED          = %00000100\n")
            out.write(f"    const ubyte ATTRF_EXPLODABLE       = %00001000\n")
            out.write(f"    const ubyte ATTRF_FALLABLE         = %00010000\n")
            out.write(f"    const ubyte ATTRF_EATABLE          = %00100000\n")
            out.write(f"    const ubyte ATTRF_ROCKFORD         = %01000000\n")
            out.write(f"    const ubyte ATTRF_LOOPINGANIM      = %10000000\n")
            out.write(f"    ubyte[NUM_OBJECTS] @shared attributes = [\n")
            for idx, flags in enumerate(attributes_flags):
                out.write(f"        {flags}")
                if idx < len(attributes_flags) - 1:
                    out.write(',')
                out.write('\n')
            out.write(f"    ]\n")
            # note: uninitialized arrays so they will be put into the BSS section.
            out.write(f"    ubyte[NUM_OBJECTS] @shared anim_frame\n")
            out.write(f"    ubyte[NUM_OBJECTS] @shared anim_delay\n")
            out.write("}\n")


    def convert_titlescreen(self):
        img = BitmapImage(self.images_directory + "/miner16.png")
        palette = img.get_vera_palette()
        assert len(palette) == 32
        open("TITLESCREEN.PAL", "wb").write(palette)
        open("TITLESCREEN.BIN", "wb").write(img.get_all_pixels_4bpp())


    def convert_font(self):
        def extract_letter(img, col, row) -> list[int]:
            result = []
            for py in range(row * 8, row * 8 + 8):
                b = 0
                for px in range(col * 8, col * 8 + 4):
                    b <<= 2
                    b |= img.getpixel((px, py))
                result.append(b)
                b = 0
                for px in range(col * 8 + 4, col * 8 + 8):
                    b <<= 2
                    b |= img.getpixel((px, py))
                result.append(b)
            assert len(result) == 16
            return result

        img = Image.open(self.images_directory + "/font2.png")
        font = bytearray(256 * 8 * 2)
        # misc
        for col in range(0, 32):
            bb = extract_letter(img, col, 0)
            font[(128 + col) * 16: (128 + col + 1) * 16] = bb
        # digits
        for col in range(0, 32):
            bb = extract_letter(img, col, 1)
            font[(32 + col) * 16: (32 + col + 1) * 16] = bb
        # uppercase letters
        for col in range(0, 32):
            bb = extract_letter(img, col, 2)
            font[(64 + 32 + col) * 16: (64 + 32 + col + 1) * 16] = bb
            font[(64 + 128 + col) * 16: (64 + 128 + col + 1) * 16] = bb
        # lowercase letters
        for col in range(0, 32):
            bb = extract_letter(img, col, 3)
            font[(64 + col) * 16: (64 + col + 1) * 16] = bb
        assert len(font) == 256 * 8 * 2
        open("FONT.BIN", "wb").write(font)


    def convert_sprites(self):
        # background sprite
        img = BitmapImage(self.images_directory + "/bgsprite.png")
        palette = img.get_vera_palette()
        assert (len(palette) <= 32)
        open("BGSPRITE.PAL", "wb").write(palette)
        open("BGSPRITE.BIN", "wb").write(img.get_all_pixels_4bpp())
        # logo sprites
        img = BitmapImage(self.images_directory + "/miner16small.png").get_image()
        # the palette should be the same as the titlescreen palette
        img_left = BitmapImage("leftlogo", img.crop((0, 0, 64, 64)))
        img_right = BitmapImage("rightlogo", img.crop((64, 0, 128, 64)))
        with open("LOGOSPRITE.BIN", "wb") as out:
            out.write(img_left.get_all_pixels_4bpp())
            out.write(img_right.get_all_pixels_4bpp())


if __name__ == '__main__':
    conv = Converter("images-classic")
    tiles_parts = conv.convert_tiles("TILES1")
    conv.make_catalog(tiles_parts)
    conv.convert_titlescreen()
    conv.convert_font()
    conv.convert_sprites()
    conv = Converter("images-new")
    _ = conv.convert_tiles("TILES2")

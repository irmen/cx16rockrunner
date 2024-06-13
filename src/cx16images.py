"""
Tools to convert bitmap images to an appropriate format for the Commander X16.
This means: indexed colors (palette), 12 bits color space (4 bits per channel, for a total of 4096 possible colors)
There are no restrictions on the size of the image.

Written by Irmen de Jong (irmen@razorvine.net) - Code is in the Public Domain.

Requirements: Pillow  (pip install pillow)
"""

from PIL import Image, PyAccess
from typing import TypeAlias

RGBList: TypeAlias = list[tuple[int, int, int]]

# the first 16 default colors of the Commander X16's color palette in (r,g,b) format
default_colors = [
    (0x0, 0x0, 0x0),  # 0 = black
    (0xf, 0xf, 0xf),  # 1 = white
    (0x8, 0x0, 0x0),  # 2 = red
    (0xa, 0xf, 0xe),  # 3 = cyan
    (0xc, 0x4, 0xc),  # 4 = purple
    (0x0, 0xc, 0x5),  # 5 = green
    (0x0, 0x0, 0xa),  # 6 = blue
    (0xe, 0xe, 0x7),  # 7 = yellow
    (0xd, 0x8, 0x5),  # 8 = orange
    (0x6, 0x4, 0x0),  # 9 = brown
    (0xf, 0x7, 0x7),  # 10 = light red
    (0x3, 0x3, 0x3),  # 11 = dark grey
    (0x7, 0x7, 0x7),  # 12 = medium grey
    (0xa, 0xf, 0x6),  # 13 = light green
    (0x0, 0x8, 0xf),  # 14 = light blue
    (0xb, 0xb, 0xb)  # 15 = light grey
]


class BitmapImage:
    def __init__(self, filename: str, image: Image = None) -> None:
        """Just load the given bitmap image file (any format allowed)."""
        if image is not None:
            self.img = image
        else:
            self.img = Image.open(filename)
        self.size = self.img.size
        self.width, self.height = self.size

    def save(self, filename: str) -> None:
        """Save the image to a new file, format based on the file extension."""
        self.img.save(filename)

    def get_image(self) -> Image:
        """Gets access to a copy of the Pillow Image class that holds the loaded image"""
        return self.img.copy()

    def crop(self, x, y, width, height) -> "BitmapImage":
        """Returns a rectangle cropped from the original image"""
        cropped = self.img.crop((x, y, x + width, y + height))
        return BitmapImage("", cropped)

    def has_palette(self) -> bool:
        """Is it an indexed colors image?"""
        return self.img.mode == "P"

    def get_palette(self) -> RGBList:
        """Return the image's palette as a list of (r,g,b) tuples"""
        return flat_palette_to_rgb(self.img.getpalette())

    def get_vera_palette(self) -> bytes:
        """
        Returns the image's palette as GB0R words (RGB in little-endian), suitable for the Vera palette registers.
        The palette must be in 12 bit color space already! Because this routine just takes the upper 4 bits of every channel value.
        """
        return rgb_palette_to_vera(self.get_palette())

    def show(self) -> None:
        """Shows the image on the screen"""
        if self.img.mode == "P":
            self.img.convert("RGB").convert("P").show()
        else:
            self.img.show()

    def get_pixels_8bpp(self, x: int, y: int, width: int, height: int) -> bytearray:
        """
        For 8 bpp (256 color) images:
        Get a rectangle of pixel values from the image, returns the bytes as a flat array
        """
        assert self.has_palette()
        try:
            access = PyAccess.new(self.img, readonly=True)
        except AttributeError:
            access = self.img
        data = bytearray(width * height)
        index = 0
        for py in range(y, y + height):
            for px in range(x, x + width):
                data[index] = access.getpixel((px, py))
                index += 1
        return data

    def get_all_pixels_8bpp(self) -> bytes:
        """
        For 8 bpp (256 color) images:
        Get all pixel values from the image, returns the bytes as a flat array
        """
        assert self.has_palette()
        return self.img.tobytes()
        # try:
        #     access = PyAccess.new(self.img, readonly=True)
        # except AttributeError:
        #     access = self.img
        # data = bytearray(self.width * self.height)
        # index = 0
        # for py in range(self.height):
        #     for px in range(self.width):
        #         data[index] = access.getpixel((px, py))
        #         index += 1
        # return data

    def get_pixels_4bpp(self, x: int, y: int, width: int, height: int) -> bytearray:
        """
        For 4 bpp (16 color) images:
        Get a rectangle of pixel values from the image, returns the bytes as a flat array.
        Every byte encodes 2 pixels (4+4 bits).
        """
        assert self.has_palette()
        try:
            access = PyAccess.new(self.img, readonly=True)
        except AttributeError:
            access = self.img
        data = bytearray(width // 2 * height)
        index = 0
        for py in range(y, y + height):
            for px in range(x, x + width, 2):
                pix1 = access.getpixel((px, py))
                pix2 = access.getpixel((px + 1, py))
                data[index] = pix1 << 4 | pix2
                index += 1
        return data

    def get_all_pixels_4bpp(self) -> bytearray:
        """
        For 4 bpp (16 color) images:
        Get all pixel values from the image, returns the bytes as a flat array.
        Every byte encodes 2 pixels (4+4 bits).
        """
        assert self.has_palette()
        try:
            access = PyAccess.new(self.img, readonly=True)
        except AttributeError:
            access = self.img
        data = bytearray(self.width // 2 * self.height)
        index = 0
        for py in range(self.height):
            for px in range(0, self.width, 2):
                pix1 = access.getpixel((px, py))
                pix2 = access.getpixel((px + 1, py))
                data[index] = pix1 << 4 | pix2
                index += 1
        return data

    def quantize(self, bits_per_pixel: int, preserve_first_16_colors: bool,
                 dither: Image.Dither = Image.Dither.FLOYDSTEINBERG) -> None:
        """
        Convert the image to one with indexed colors (12 bits colorspace palette extended back into 8 bits per channel).
        If you want to display the image on the actual Commander X16, simply take the lower (or upper) 4 bits of every color channel.
        There is support for either 8 or 4 bits per pixel (256 or 16 color modes).
        Dithering is applied as given (default is Floyd-Steinberg).
        """
        if bits_per_pixel == 8:
            num_colors = 240 if preserve_first_16_colors else 256
        elif bits_per_pixel == 4:
            num_colors = 16
        else:
            raise ValueError("only 8 or 4 bpp supported")
        palette_image = self.make_quantization_palette_from_image(num_colors, preserve_first_16_colors)
        self.img = self.img.quantize(dither=dither, palette=palette_image)

    def make_quantization_palette_from_image(self, num_colors: int, preserve_first_16_colors: bool) -> Image:
        if num_colors == 16 and preserve_first_16_colors:
            palette_image = Image.new("P", (1, 1))
            palette = []
            for r, g, b in default_colors:
                palette.append(r << 4 | r)
                palette.append(g << 4 | g)
                palette.append(b << 4 | b)
            palette_image.putpalette(palette)
            return palette_image
        else:
            image = self.img.convert("RGB")
            palette_image = image.quantize(colors=num_colors, dither=Image.Dither.NONE, method=Image.Quantize.MAXCOVERAGE)
            if len(palette_image.getpalette()) // 3 > num_colors:
                palette_image = image.quantize(colors=num_colors - 1, dither=Image.Dither.NONE, method=Image.Quantize.MAXCOVERAGE)
            palette_rgb = flat_palette_to_rgb(palette_image.getpalette())
            palette_rgb = list(set(palette_8to4(palette_rgb)))
            if preserve_first_16_colors:
                palette_rgb = default_colors + palette_rgb
            palette = []
            for r, g, b in sorted(palette_rgb):
                palette.append(r << 4 | r)
                palette.append(g << 4 | g)
                palette.append(b << 4 | b)
            palette_image.putpalette(palette)
            return palette_image

    def constrain_size(self, hires: bool = False) -> None:
        """
        If the image is larger than the lores or hires screen size, scale it down so that it fits.
        If the image already fits, doesn't do anything.
        """
        w, h = self.img.size
        if hires and (w > 640 or h > 480):
            self.img.thumbnail((640, 480))
        elif w > 320 or h > 240:
            self.img.thumbnail((320, 240))
        self.size = self.img.size
        self.width, self.height = self.size


# utility functions

def channel_8to4(color: int) -> int:
    """Accurate conversion of a single 8 bit color channel value to 4 bits"""
    return (color * 15 + 135) >> 8  # see https://threadlocalmutex.com/?p=48


def palette_8to4(palette_rgb: RGBList) -> RGBList:
    """Accurate conversion of a 24 bits palette (8 bits per channel) to a 12 bits palette (4 bits per channel)"""
    converted = []
    for ci in range(len(palette_rgb)):
        r, g, b = palette_rgb[ci]
        converted.append((channel_8to4(r), channel_8to4(g), channel_8to4(b)))
    return converted


def reduce_colorspace(palette_rgb: RGBList) -> RGBList:
    """
    Convert 24 bits color space (8 bits per channel) to 12 bits color space (4 bits per channel).
    The resulting color values are still full 8 bits but their precision is reduced.
    You can take either the upper or lower 4 bits of each channel byte to get the actual 4 bits precision.
    """
    converted = []
    for r, g, b in palette_rgb:
        r = channel_8to4(r)
        g = channel_8to4(g)
        b = channel_8to4(b)
        converted.append((r << 4 | r, g << 4 | g, b << 4 | b))
    return converted


def flat_palette_to_rgb(palette: list[int]) -> RGBList:
    """Converts the flat palette list usually obtained from Pillow images to a list of (r,g,b) tuples"""
    return [(palette[i], palette[i + 1], palette[i + 2]) for i in range(0, len(palette), 3)]


def rgb_palette_to_flat(palette: RGBList) -> list[int]:
    """Convert a palette of (r,g,b) tuples to a flat list that is usually used by Pillow images"""
    result = []
    for r, g, b in palette:
        result.append(r)
        result.append(g)
        result.append(b)
    return result


def flat_palette_to_vera(palette: list[int]) -> bytearray:
    """
    Convert a flat palette list usually obtained from Pillow images, to GB0R words (RGB in little-endian), suitable for Vera palette registers.
    The palette must be in 12 bit color space already! Because this routine just takes the upper 4 bits of every channel value.
    """
    return rgb_palette_to_vera(flat_palette_to_rgb(palette))


def rgb_palette_to_vera(palette_rgb: RGBList) -> bytearray:
    """
    Convert a palette in (r,g,b) format to GB0R words (RGB in little-endian), suitable for Vera palette registers.
    The palette must be in 12 bit color space already! Because this routine just takes the upper 4 bits of every channel value.
    """
    data = bytearray()
    for r, g, b in palette_rgb:
        r = r >> 4
        g = g >> 4
        b = b >> 4
        data.append(g << 4 | b)
        data.append(r)
    return data

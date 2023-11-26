.PHONY: all clean emu zip

all: ROCKRUNNER.PRG

clean:
	rm -f *.prg *.PRG *.asm *.vice-* *.BIN *.PAL *.ADPCM *.zip *.7z converted.png src/objects.p8
	rm -f HISCORES/*.DAT

emu: ROCKRUNNER.PRG
	PULSE_LATENCY_MSEC=20 x16emu -abufs 16 -scale 2 -quality best -run -prg $<

emu2: ROCKRUNNER.PRG
	PULSE_LATENCY_MSEC=20 box16 -scale 2 -run -prg $<

src/objects.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL: src/convert_images.py images/catalog.ini
	@python src/convert_images.py

ROCKRUNNER.PRG: src/*.p8 src/objects.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL
	@p8compile src/rockrunner.p8 -target cx16
	@mv rockrunner.prg ROCKRUNNER.PRG

zip: all
	rm -f rockrunner.zip
	7z a rockrunner.zip ROCKRUNNER.PRG TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL CAVES HISCORES manifest.json

bdcffreadertest: BDCFFTEST.PRG
	PULSE_LATENCY_MSEC=20 x16emu -abufs 16 -scale 2 -run -prg $<

BDCFFTEST.PRG: src/*.p8
	@p8compile src/bdcfftest.p8 -target cx16
	@mv bdcfftest.prg BDCFFTEST.PRG


.PHONY: all clean run run2 zip

PROG8C ?= prog8c       # if that fails, try this alternative (point to the correct jar file location): java -jar prog8c.jar
PYTHON ?= python
ZIP ?= zip


all: ROCKRUNNER.PRG

clean:
	rm -f *.prg *.PRG *.asm *.vice-* *.BIN *.PAL *.ADPCM *.zip *.7z converted.png src/objects.p8
	rm -f HISCORES/*.DAT

run: ROCKRUNNER.PRG
	PULSE_LATENCY_MSEC=20 x16emu -abufs 16 -scale 2 -quality best -run -prg $<

run2: ROCKRUNNER.PRG
	PULSE_LATENCY_MSEC=20 box16 -scale 2 -run -prg $<

src/objects.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL LOGOSPRITE.BIN: src/convert_images.py images/catalog.ini
	@$(PYTHON) src/convert_images.py

ROCKRUNNER.PRG: src/*.p8 src/objects.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL LOGOSPRITE.BIN
	$(PROG8C) src/rockrunner.p8 -target cx16
	@mv rockrunner.prg ROCKRUNNER.PRG

zip: all
	rm -f rockrunner.zip
	$(ZIP) -r rockrunner.zip ROCKRUNNER.PRG TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL FONT.BIN BGSPRITE.BIN BGSPRITE.PAL LOGOSPRITE.BIN CAVES HISCORES/README.TXT manifest.json

bdcffreadertest: BDCFFTEST.PRG
	PULSE_LATENCY_MSEC=20 x16emu -abufs 16 -scale 2 -run -prg $<

BDCFFTEST.PRG: src/*.p8
	@$(PROG8C) src/bdcfftest.p8 -target cx16
	@mv bdcfftest.prg BDCFFTEST.PRG


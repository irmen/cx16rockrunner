.PHONY: all clean emu zip

all: BOULDER.PRG

clean:
	rm -f *.prg *.PRG *.asm *.vice-* *.BIN *.PAL *.ADPCM *.zip *.7z converted.png src/objects.p8

emu:  BOULDER.PRG
	# PULSE_LATENCY_MSEC=20 box16 -scale 2 -run -prg $<
	PULSE_LATENCY_MSEC=20 x16emu -scale 2 -quality best -run -prg $<

src/objects.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL: src/convert_images.py images/catalog.ini
	@python src/convert_images.py

BOULDER.PRG: src/*.p8 TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREEN.PAL
	@p8compile src/boulder.p8 -target cx16
	@mv boulder.prg BOULDER.PRG

zip: all
	7z a boulder.zip BOULDER.PRG TILES.BIN TILES.PAL TITLESCREEN.BIN TITLESCREN.PAL

	
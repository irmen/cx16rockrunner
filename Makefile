.PHONY: all clean emu

all: TILES.BIN TILES.PAL SHOW.PRG

clean:
	rm -f *.prg *.PRG *.asm *.vice-* *.BIN *.PAL *.ADPCM *.zip *.7z src/objects.p8

emu:  SHOW.PRG
	# PULSE_LATENCY_MSEC=20 box16 -scale 2 -run -prg $<
	PULSE_LATENCY_MSEC=20 x16emu -scale 2 -quality best -run -prg $<

TILES.BIN: src/convert_images.py images/catalog.ini
	@python src/convert_images.py

src/objects.p8: src/convert_images.py images/catalog.ini
	@python src/convert_images.py

SHOW.PRG: src/show.p8 src/objects.p8
	@p8compile $< -target cx16
	@mv show.prg SHOW.PRG


.PHONY: all clean emu

all: TILES.BIN TILES.PAL SHOW.PRG

clean:
	rm -f *.prg *.PRG *.asm *.vice-* *.BIN *.PAL *.ADPCM *.zip *.7z

emu:  SHOW.PRG
	# PULSE_LATENCY_MSEC=20 box16 -scale 2 -run -prg $<
	PULSE_LATENCY_MSEC=20 x16emu -scale 2 -quality best -run -prg $<

TILES.BIN: src/convert_images.py
	@python src/convert_images.py

SHOW.PRG: src/show.p8
	@p8compile $< -target cx16
	@mv show.prg SHOW.PRG


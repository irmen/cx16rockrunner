%import diskio
%import cx16diskio

main {
    sub start() {
        load_tiles()
        lores256()

        ; clear the whole tile map with all transparent space tiles.
        uword vv
        for vv in $b000 to $b000+2*64*32-1 step 2 {
            cx16.vpoke(1, vv, 74)
            cx16.vpoke(1, vv+1, $20)
        }

        ; draw all 287 tiles
        ;images/bd_bluethings.png tile offset=0 palette offset=0 (48 tiles)
        ;images/bd_explosions.png tile offset=48 palette offset=1 (24 tiles)
        ;images/bd_grass.png tile offset=72 palette offset=2 (16 tiles)
        ;images/bd_metals.png tile offset=88 palette offset=3 (32 tiles)
        ;images/bd_misc1.png tile offset=120 palette offset=4 (16 tiles)
        ;images/bd_misc2.png tile offset=136 palette offset=5 (7 tiles)
        ;images/bd_orangethings.png tile offset=143 palette offset=6 (56 tiles)
        ;images/bd_player.png tile offset=199 palette offset=7 (64 tiles)
        ;images/bd_rocks.png tile offset=263 palette offset=8 (8 tiles)
        ;images/bd_walls.png tile offset=271 palette offset=9 (16 tiles)

        ubyte column = 0
        ubyte row = 0
        draw_tiles(0, 48, 0)
        draw_tiles(48, 24, 1)
        draw_tiles(72, 16, 2)
        draw_tiles(88, 32, 3)
        draw_tiles(120, 16, 4)
        draw_tiles(136, 7, 5)
        draw_tiles(143, 56, 6)
        draw_tiles(199, 64, 7)
        draw_tiles(263, 8, 8)
        draw_tiles(271, 16, 9)

        repeat {

        }

        sub draw_tiles(uword tile_index, ubyte num_tiles, ubyte palette_offset) {
            repeat num_tiles {
                uword vaddr = $b000+column*$0002+(row*$0080)
                cx16.vpoke(1, vaddr, lsb(tile_index))
                cx16.vpoke(1, vaddr+1, palette_offset<<4 | msb(tile_index))
                tile_index++
                column++
                if column==20 {
                    column=0
                    row++
                }
            }
            row++
            column = 0
        }
    }

    sub lores256() {
        ; 320x240 tile layer (#1), 4bpp (16 colors) per tile, 16x16 tiles.
        ; 64x32 tile map at $1B000
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO & $0f | %00100000       ; layer 1 active
        cx16.VERA_DC_HSCALE = 64
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L1_CONFIG = %00010010
        cx16.VERA_L1_MAPBASE = ($1B000 >> 9) as ubyte
        cx16.VERA_L1_TILEBASE = %00000011
    }

    sub load_tiles() {
        if not cx16diskio.vload_raw("tiles.pal", 8, 1, $fa00)
           or not cx16diskio.vload_raw("tiles.bin", 8, 0, $0000) {
            txt.print("load error\n")
            sys.exit(1)
        }
    }
}

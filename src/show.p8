%import diskio
%import cx16diskio
%import objects

main {
    uword cells = memory("objects_matrix", 64*32, 256)
    uword cell_anims = memory("anim_matrix", 64*32, 256)

    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    sub start() {
        sys.memset(cells, 64*32, objects.space)
        sys.memset(cell_anims, 64*32, 0)
        load_tiles()
        lores256()

        ubyte xx
        ubyte yy
        ubyte obj_id = 0
        for yy in 0 to VISIBLE_CELLS_V-1 {
            for xx in 0 to VISIBLE_CELLS_H-1 {
                cells[yy*$0040 + xx] = obj_id
                obj_id++
                if obj_id >= objects.NUM_OBJECTS
                    obj_id=0
            }
        }

        repeat {
            sys.waitvsync()
            draw_screen()
        }

        sub draw_screen() {
            ; This fills the visible part of the screen in video ram with the tiles for all cells.
            ; TODO take viewable X,Y offsets in to account
            uword @requirezp cell_ptr
            uword @requirezp anim_ptr
            ubyte @zp row
            for row in 0 to VISIBLE_CELLS_V {
                cx16.vaddr(1, $b000 + row*$0080, 0, 1)
                cell_ptr = cells + row*$0040
                anim_ptr = cell_anims + row*$0040
                %asm {{
                    phx
                    ldx  #main.VISIBLE_CELLS_H
-                   lda  (cell_ptr)
                    clc
                    adc  (anim_ptr)
                    tay
                    lda  objects.tile_lo,y
                    sta  cx16.VERA_DATA0
                    lda  objects.palette_offsets_preshifted,y
                    ora  objects.tile_hi,y
                    sta  cx16.VERA_DATA0
                    inc  cell_ptr
                    bne  +
                    inc  cell_ptr+1
+                   inc  anim_ptr
                    bne  +
                    inc  anim_ptr+1
+                   dex
                    bne  -
                    plx
                }}
            }
        }

        sub draw_tile(ubyte col, ubyte row, ubyte id) {
            @(cells+(row as uword)*64+col) = id
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

%import diskio
%import cx16diskio
%import objects

main {
    uword @requirezp cell_ptr
    uword @requirezp anims_ptr

    sub start() {
        ;; titlescreen()
        ;; sys.wait(120)
        cave.init()
        load_tiles()
        set_tiles_screenmode()
        fill_demotiles()

        repeat {
            update_animation()
            sys.waitvsync()
            draw_screen()
        }
    }

    sub titlescreen() {
        ; 320x240 bitmap mode 4bpp (16 colors)
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO & $0f | %00010000       ; layer 0 active
        cx16.VERA_DC_HSCALE = 64
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L0_CONFIG = %00000110
        cx16.VERA_L0_TILEBASE = 0

        if not cx16diskio.vload_raw("titlescreen.pal", 8, 1, $fa00)
           or not cx16diskio.vload_raw("titlescreen.bin", 8, 0, $0000) {
            txt.print("load error\n")
            sys.exit(1)
        }
    }

    sub load_tiles() {
        if not cx16diskio.vload_raw("tiles.pal", 8, 1, $fa00)
           or not cx16diskio.vload_raw("tiles.bin", 8, 0, $0000) {
            txt.print("load error\n")
            sys.exit(1)
        }
    }

    sub update_animation() {
        ; increase anim frame count of all animate objects
        ; once they reach their target frame, set it to 0 which will trigger the next animation tile in the sequence
        ; cx16.vpoke(1,$fa00,$f0)
        ubyte idx
        for idx in 0 to objects.NUM_OBJECTS {
            cx16.r1L = objects.anim_speeds[idx]
            if_nz {
                cx16.r0L = objects.anim_frames[idx]
                cx16.r0L++
                if cx16.r0L >= cx16.r1L
                    cx16.r0L = 0
                objects.anim_frames[idx] = cx16.r0L
            }
        }

        cell_ptr = cave.cells
        anims_ptr = cave.cell_anims
        repeat cave.MAX_CAVE_HEIGHT {
            repeat cave.MAX_CAVE_WIDTH {
                %asm {{
                    lda  (cell_ptr)
                    tay
                    lda  objects.anim_frames,y
                    bne  _no_anim
                    lda  objects.anim_sizes,y
                    sta  cx16.r0L
                    lda  (anims_ptr)
                    ina
                    cmp  cx16.r0L
                    bne  +
                    lda  #0
+                   sta  (anims_ptr)
_no_anim
                }}
                cell_ptr++
                anims_ptr++
            }
        }
        ; cx16.vpoke(1,$fa00,$00)
    }

    sub draw_screen() {
        ; This fills the visible part of the screen in video ram with the tiles for all cells.
        ; TODO take viewable X,Y offsets in to account
        ; cx16.vpoke(1,$fa00,$0f)
        ubyte @zp row
        for row in 0 to cave.VISIBLE_CELLS_V {
            cx16.vaddr(1, $b000 + row*$0080, 0, 1)
            uword offset = (row as uword)*cave.MAX_CAVE_WIDTH
            cell_ptr = cave.cells + offset
            anims_ptr = cave.cell_anims + offset
            %asm {{
                phx
                ldx  #cave.VISIBLE_CELLS_H
-               lda  (cell_ptr)
                tay
                lda  objects.tile_lo,y
                clc
                adc  (anims_ptr)
                sta  cx16.VERA_DATA0
                lda  objects.palette_offsets_preshifted,y
                adc  #0
                ora  objects.tile_hi,y
                sta  cx16.VERA_DATA0
                inc  cell_ptr
                bne  +
                inc  cell_ptr+1
+               inc  anims_ptr
                bne  +
                inc  anims_ptr+1
+               dex
                bne  -
                plx
            }}
        }
        ; cx16.vpoke(1,$fa00,$00)
    }

    sub fill_demotiles() {
        ubyte xx
        ubyte yy
        ubyte @zp obj_id = 0
        for yy in 0 to cave.VISIBLE_CELLS_V-1 {
            for xx in 0 to cave.VISIBLE_CELLS_H-1 {
                cave.cells[(yy as uword)*cave.MAX_CAVE_WIDTH + xx] = obj_id
                obj_id++
                if obj_id >= objects.NUM_OBJECTS
                    obj_id=0
            }
        }
    }

    sub set_tiles_screenmode() {
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
}

cave {
    ; for now we use the original cave dimension limits
    const ubyte MAX_CAVE_WIDTH = 40
    const ubyte MAX_CAVE_HEIGHT = 22
    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword cell_anims = memory("anim_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)

    sub init() {
        sys.memset(cells, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, objects.space)
        sys.memset(cell_anims, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 0)
    }

    sub draw_tile(ubyte col, ubyte row, ubyte id) {
        uword offset = (row as uword)*MAX_CAVE_WIDTH+col
        @(cells+offset) = id
        @(cell_anims+offset) = 0
    }
}

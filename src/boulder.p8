%import diskio
%import cx16diskio
%import objects
%import cave
%import bd1caves

main {
    uword @requirezp cell_ptr

    sub start() {
        ;; titlescreen()
        ;; sys.wait(120)
        cave.init()
        load_tiles()
        set_tiles_screenmode()
        ; cave.fill_demotiles()

        ubyte level = 0
        bd1caves.decode(level)
        ubyte switch_level=0
        ubyte frame

        repeat {
            update_animations()
            sys.waitvsync()
            scroll(sx, sy)
            draw_screen()
            update_scrollpos()
            switch_level++
            if switch_level==120 {
                switch_level=0
                level++
                if level==bd1caves.NUM_CAVES
                    level=0
                bd1caves.decode(level)
            }
            frame++
        }
    }

    uword sx
    uword sy
    byte sdx=1
    byte sdy=1

    sub update_scrollpos() {
        sx += sdx as uword
        sy += sdy as uword
        if sx==0 or sx >= (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)*16
            sdx = -sdx
        if sy==0 or sy >= (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)*16
            sdy = -sdy
    }

    sub scroll(uword sx, uword sy) {
        ; smooth scroll the screen to top left pixel at sx, sy
        cx16.VERA_L1_HSCROLL_H = msb(sx)
        cx16.VERA_L1_HSCROLL_L = lsb(sx)
        cx16.VERA_L1_VSCROLL_H = msb(sy)
        cx16.VERA_L1_VSCROLL_L = lsb(sy)
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

    sub update_animations() {
        ; increase anim delay counter of all animate objects
        ; once they reach their target, set it to 0 which will trigger the next animation tile in the sequence
        ; cx16.vpoke(1,$fa00,$f0)
        ubyte idx
        for idx in 0 to objects.NUM_OBJECTS {
            if objects.anim_speeds[idx] {
                cx16.r0L = objects.anim_delay[idx]
                cx16.r0L++
                if cx16.r0L >= objects.anim_speeds[idx] {
                    cx16.r0L = 0
                    cx16.r1L = objects.anim_frame[idx]
                    cx16.r1L++
                    if cx16.r1L == objects.anim_sizes[idx]
                        cx16.r1L = 0
                    objects.anim_frame[idx] = cx16.r1L
                }
                objects.anim_delay[idx] = cx16.r0L
            }
        }
        ; cx16.vpoke(1,$fa00,$00)
    }

    sub draw_screen() {
        ; set the tiles in video ram for the visible cells.
        ; cx16.vpoke(1,$fa00,$0f)
        ubyte row_offset = lsb(sy/16)
        ubyte col_offset = lsb(sx/16)
        ubyte @zp row
        for row in row_offset to row_offset+cave.VISIBLE_CELLS_V {
            cx16.vaddr(1, $b000 + row*$0080 + col_offset*2, 0, 1)
            cell_ptr = cave.cells + (row as uword)*cave.MAX_CAVE_WIDTH + col_offset
            repeat cave.VISIBLE_CELLS_H+1 {
                %asm {{
                    lda  (cell_ptr)
                    tay
                    lda  objects.tile_lo,y
                    clc
                    adc  objects.anim_frame,y
                    sta  cx16.VERA_DATA0
                    lda  objects.palette_offsets_preshifted,y
                    adc  #0
                    ora  objects.tile_hi,y
                    sta  cx16.VERA_DATA0
                    inc  cell_ptr
                    bne  +
                    inc  cell_ptr+1
+
                }}
            }
        }
        ; cx16.vpoke(1,$fa00,$00)
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


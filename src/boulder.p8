%import diskio
%import cx16diskio
%import psg
%import palette
%import objects
%import cave
%import bd1caves

main {
    sub start() {
        music.init()
        palette.set_all_black()
        screen.titlescreen()
        cx16.set_irq(&interrupts.handler, true)
        music.playback_enabled = true
        sys.wait(120)
        palette.set_all_black()
        cave.init()
        screen.set_tiles_screenmode()
        screen.load_tiles()

        bd1caves.decode(8)

        repeat {
            ; the game loop, executed every frame.
            interrupts.waitvsync()
            screen.update()
            screen.update_animations()
            cave.scan()
        }
    }
}

screen {
    uword @requirezp cell_ptr
    uword scrollx
    uword scrolly
    byte scrolldx=1
    byte scrolldy=1

    sub update_scrollpos() {
        scrollx += scrolldx as uword
        scrolly += scrolldy as uword
        if scrollx==0 or scrollx >= (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)*16
            scrolldx = -scrolldx
        if scrolly==0 or scrolly >= (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)*16
            scrolldy = -scrolldy
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

        if not cx16diskio.vload_raw("titlescreen.bin", 8, 0, $0000)
           or not cx16diskio.vload_raw("titlescreen.pal", 8, 1, $fa00) {
            txt.print("load error\n")
            sys.exit(1)
        }
    }

    sub load_tiles() {
        if not cx16diskio.vload_raw("tiles.bin", 8, 0, $0000)
           or not cx16diskio.vload_raw("tiles.pal", 8, 1, $fa00) {
            txt.print("load error\n")
            sys.exit(1)
        }
        sys.wait(1)
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

    sub update() {
        ; set the tiles in video ram for the visible cells.
        ; cx16.vpoke(1,$fa00,$0f)
        ubyte row_offset = lsb(scrolly/16)
        ubyte col_offset = lsb(scrollx/16)
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

interrupts {
    ubyte vsync_counter = 0
    ubyte vsync_semaphore = 1

    asmsub waitvsync() {
        ; an improved waitvsync() routine over the one in the sys lib
        %asm {{
-           wai
            lda  vsync_semaphore
            bne  -
            inc  vsync_semaphore
            rts
        }}
    }

    sub handler() {
        if cx16.VERA_ISR & %00000001 {
            vsync_semaphore=0
            vsync_counter++
            cx16.push_vera_context()
            ; soft-scrolling is handled in the irq handler itself to avoid stutters
            screen.scroll(screen.scrollx, screen.scrolly)
            screen.update_scrollpos()
            music.update()
            psg.envelopes_irq()
            cx16.pop_vera_context()
        }
    }
}

music {

    ; details about the boulderdash music can be found here:
    ; https://www.elmerproductions.com/sp/peterb/sounds.html#Theme%20tune

    sub init() {
         psg.silent()
         psg.voice(0, psg.LEFT, 0, psg.TRIANGLE, 0)
         psg.voice(1, psg.RIGHT, 0, psg.TRIANGLE, 0)
         note_idx = 0
         playback_enabled = false
    }

    bool playback_enabled
    ubyte note_idx
    ubyte update_cnt

    sub update() {
        if not playback_enabled
            return

        update_cnt++
        if update_cnt==10
            update_cnt = 0
        else
            return
        uword note = notes[note_idx]
        note_idx++
        if note_idx >= len(notes)
            note_idx = 0
        ubyte note0 = lsb(note)
        ubyte note1 = msb(note)
        psg.freq(0, vera_freqs[note0])
        psg.freq(1, vera_freqs[note1])
        psg.envelope(0, 63, 255, 0, 6)
        psg.envelope(1, 63, 255, 0, 6)
    }

    uword[] notes = [
        $1622, $1d26, $2229, $252e, $1424, $1f27, $2029, $2730,
        $122a, $122c, $1e2e, $1231, $202c, $3337, $212d, $3135,
        $1622, $162e, $161d, $1624, $1420, $1430, $1424, $1420,
        $1622, $162e, $161d, $1624, $1e2a, $1e3a, $1e2e, $1e2a,
        $142c, $142c, $141b, $1422, $1c28, $1c38, $1c2c, $1c28,
        $111d, $292d, $111f, $292e, $0f27, $0f27, $1633, $1627,
        $162e, $162e, $162e, $162e, $222e, $222e, $162e, $162e,
        $142e, $142e, $142e, $142e, $202e, $202e, $142e, $142e,
        $162e, $322e, $162e, $332e, $222e, $322e, $162e, $332e,
        $142e, $322e, $142e, $332e, $202c, $302c, $142c, $312c,
        $162e, $163a, $162e, $3538, $222e, $2237, $162e, $3135,
        $142c, $1438, $142c, $1438, $202c, $2033, $142c, $1438,
        $162e, $322e, $162e, $332e, $222e, $322e, $162e, $332e,
        $142e, $322e, $142e, $332e, $202c, $302c, $142c, $312c,
        $2e32, $292e, $2629, $2226, $2c30, $272c, $2427, $1420,
        $3532, $322e, $2e29, $2926, $2730, $242c, $2027, $1420
    ]

    uword[] vera_freqs = [
        0,0,0,0,0,0,0,0,0,0,   ; first 10 notes are not used
        120, 127, 135, 143, 152, 160, 170, 180, 191, 203,
        215, 227, 240, 255, 270, 287, 304, 320, 341, 360,
        383, 405, 429, 455, 479, 509, 541, 573, 607, 640,
        682, 720, 766, 810, 859, 910, 958, 1019, 1082, 1147,
        1215, 1280, 1364, 1440, 1532, 1621, 1718, 1820, 1917]

}

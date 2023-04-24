%import conv
%import diskio
%import cx16diskio
%import psg
%import palette
%import objects
%import cave
%import bd1caves
%import bdcff
%import sounds

main {
    ubyte joystick = 0      ; TODO make this selectable
    ubyte game_state

    const ubyte STATE_CAVETITLE = 1
    const ubyte STATE_UNCOVERING = 2
    const ubyte STATE_PLAYING = 3
    const ubyte STATE_GAMEOVER = 4

    sub start() {
        music.init()
        ;; screen.titlescreen()
        cx16.set_irq(&interrupts.handler, true)
        ;; music.playback_enabled = true
        ;; sys.wait(120)
        cave.init()
        screen.set_tiles_screenmode()
        screen.disable()
        screen.load_tiles()
        bdcff.load_test_cave()
        ;; bd1caves.decode(2)      ; load level 1, the first level
        bd1demo.init()
        cave.num_lives = 3
        cave.score = 0
        cave.score_500_for_bonus = 0
        cave.restart_level()
        ;; cave.playing_demo=true
        screen.enable()
        music.playback_enabled = false

        ubyte title_timer = 255
        screen.show_cave_title()
        game_state = STATE_CAVETITLE

        repeat {
            ; the game loop, executed every frame.
            ; TODO difficulty level that influences play speed, see https://www.elmerproductions.com/sp/peterb/insideBoulderdash.html#Timing%20info
            interrupts.waitvsync()
            screen.update()

            when game_state {
                STATE_CAVETITLE -> {
                    title_timer--
                    if_z {
                        cx16.r0 = (math.rnd() % (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)) * $0010
                        cx16.r1 = (math.rnd() % (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)) * $0010
                        screen.set_scroll_pos(cx16.r0, cx16.r1)
                        screen.hud_clear()
                        if cave.playing_demo {
                            screen.hud_text(12,13,$f0,"**** Playing ****")
                            screen.hud_text(12,16,$f0,"****  Demo   ****")
                        }
                        game_state = STATE_UNCOVERING
                    }
                }
                STATE_UNCOVERING -> {
                    cave.uncover_more()
                    if not cave.covered
                        game_state = STATE_PLAYING
                }
                STATE_PLAYING -> {
                    cave.scan()
                    if interrupts.vsync_counter % 3 == 0
                        screen.hud_update()
                    ; TODO wait for user, restart covered level if lives>0 else game over.
                }
                STATE_GAMEOVER -> {
                    ; TODO game over screen
                }
            }
        }
    }
}

screen {
    word scrollx
    word scrolly
    bool scrolling_into_view_x = false
    bool scrolling_into_view_y = false

    sub set_scroll_pos(uword sx, uword sy) {
        scrollx = sx as word
        scrolly = sy as word
    }

    ubyte old_vera_displaymode
    sub disable() {
        old_vera_displaymode = cx16.VERA_DC_VIDEO
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_VIDEO &= %10001111
    }
    sub enable() {
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_VIDEO = old_vera_displaymode
    }

    sub update() {
        ; set the tiles in video ram for the visible cells.
        ; cx16.vpoke(1,$fa00,$0f)
        ubyte row_offset = lsb(scrolly/16)
        ubyte col_offset = lsb(scrollx/16)
        ubyte @zp row
        for row in row_offset to row_offset+cave.VISIBLE_CELLS_V {
            cx16.vaddr(1, $b000 + row*$0080 + col_offset*2, 0, 1)
            uword cells_offset = row*cave.MAX_CAVE_WIDTH + col_offset
            uword @requirezp @shared cell_ptr = cave.cells + cells_offset
            uword @requirezp @shared attr_ptr = cave.cell_attributes + cells_offset
            %asm {{
                phx
                ldy  #0
_loop           lda  (attr_ptr),y
                and  #cave.ATTR_COVERED_FLAG
                beq  +
                ldx  #objects.covered
                bra  ++
+               lda  (cell_ptr),y
                tax
+               lda  objects.tile_lo,x
                clc
                adc  objects.anim_frame,x
                sta  cx16.VERA_DATA0
                lda  objects.tile_hi,x
                adc  objects.palette_offsets_preshifted,x
                sta  cx16.VERA_DATA0
                iny
                cpy  #cave.VISIBLE_CELLS_H+1
                bne  _loop
                plx
            }}
        }
        ; cx16.vpoke(1,$fa00,$00)
        screen.update_animations()
        screen.update_scrollpos()
    }

    sub update_scrollpos() {
        ; try to recenter rockford in the visible screen
        word target_scrollx = (cave.player_x as word - cave.VISIBLE_CELLS_H/2) * 16
        word target_scrolly = (cave.player_y as word - cave.VISIBLE_CELLS_V/2) * 16
        word dx = target_scrollx - scrollx
        word dy = target_scrolly - scrolly
        if not scrolling_into_view_x {
            if abs(dx) < cave.VISIBLE_CELLS_H/4*16
                dx = 0
            else
                scrolling_into_view_x = true
        }
        if not scrolling_into_view_y {
            if abs(dy) < cave.VISIBLE_CELLS_V/4*16
                dy = 0
            else
                scrolling_into_view_y = true
        }

        scrolling_into_view_x = dx!=0
        scrolling_into_view_y = dy!=0
        if scrolling_into_view_x {
            dx >>= 5
            if dx==0
                scrollx++
            else
                scrollx += dx
        }
        if scrolling_into_view_y {
            dy >>= 5
            if dy==0
                scrolly++
            else
                scrolly += dy
        }
        if scrollx < 0
            scrollx = 0
        if scrolly < 0
            scrolly = 0
        if scrollx > (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)*16
            scrollx = (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)*16
        if scrolly > (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)*16
            scrolly = (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)*16
    }

    sub titlescreen() {
        ; 320x240 bitmap mode 4bpp (16 colors)
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_BORDER = 0
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO & %10001111      ; no layers visible
        cx16.VERA_DC_HSCALE = 64
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L0_CONFIG = %00000110
        cx16.VERA_L0_TILEBASE = 0

        void cx16diskio.vload_raw("titlescreen.bin", 8, 0, $0000)
        void cx16diskio.vload_raw("titlescreen.pal", 8, 1, $fa00)
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO | %00010000       ; layer 0 active
    }

    sub load_tiles() {
        void cx16diskio.vload_raw("tiles.bin", 8, 0, $0000)
        void cx16diskio.vload_raw("tiles.pal", 8, 1, $fa00)
        void cx16diskio.vload_raw("font.bin", 8, 1, $e000)
        ; fixup the palette for the HUD text font (entries $f0-$ff)
        cx16.vpoke(1,$fa00+$f0*2,$00)
        cx16.vpoke(1,$fa00+$f0*2+1,$00)
        cx16.vpoke(1,$fa00+$f1*2,$24)
        cx16.vpoke(1,$fa00+$f1*2+1,$05)
        cx16.vpoke(1,$fa00+$f2*2,$ff)
        cx16.vpoke(1,$fa00+$f2*2+1,$0f)
        cx16.vpoke(1,$fa00+$f2*3,$f0)
        cx16.vpoke(1,$fa00+$f2*3+1,$ff)
    }

    sub update_animations() {
        ; increase anim delay counter of all animate objects
        ; once they reach their target, set it to 0 which will trigger the next animation tile in the sequence
        ; cx16.vpoke(1,$fa00,$f0)
        ubyte idx
        for idx in 0 to objects.NUM_OBJECTS-1 {
            if objects.anim_speeds[idx] {
                cx16.r0L = objects.anim_delay[idx]
                cx16.r0L++
                if cx16.r0L == objects.anim_speeds[idx] {
                    cx16.r0L = 0
                    cx16.r1L = objects.anim_frame[idx]
                    cx16.r1L++
                    if cx16.r1L == objects.anim_sizes[idx] {
                        if objects.attributes[idx] & objects.ATTRF_LOOPINGANIM
                            cx16.r1L = 0
                        else
                            cx16.r1L--
                        objects.anim_cycles[idx]++
                    }
                    objects.anim_frame[idx] = cx16.r1L
                }
                objects.anim_delay[idx] = cx16.r0L
            }
        }
        ; cx16.vpoke(1,$fa00,$00)
    }

    sub set_tiles_screenmode() {
        ; video setup:
        ; layer 0 = tile layer for the cave itself.
        ;           320x240 pixels, 4bpp (16 colors) 16x16 tiles.
        ;           tile map: 64x32 tiles at $1B000.
        ; layer 1 = tile layer for the text/HUD/score/time/etc.
        ;           320x240 pixels, 4bpp (16 colors) 16x16 tiles.
        ;           tile map: 64x32 tiles at $1C000.
        ;           uses font data at $1E000
        ; no sprites.

        ; pre-fill screen with space tiles
        cx16.vaddr(1, $b000, 0, 1)
        ubyte space_tile = objects.tile_lo[objects.space]
        repeat 64*32 {
            cx16.VERA_DATA0 = space_tile
            cx16.VERA_DATA0 = 0
        }
        hud_clear()

        cx16.VERA_CTRL = 0
        cx16.VERA_DC_BORDER = 0
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO & $0f | %00110000       ; layer 0 and 1 active
        cx16.VERA_DC_HSCALE = 64
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L0_CONFIG = %00010010                 ; 64x32 tiles, 4bpp
        cx16.VERA_L0_MAPBASE = ($1B000 >> 9) as ubyte
        cx16.VERA_L0_TILEBASE = %00000011               ; 16x16 pixel tiles
        cx16.VERA_L1_CONFIG = %00010001                 ; 64x32 tiles, 2bpp
        cx16.VERA_L1_MAPBASE = ($1C000 >> 9) as ubyte
        cx16.VERA_L1_TILEBASE = ($1E000 >>9) as ubyte | %00000000               ; 8x8 pixel tiles
    }

    sub hud_clear() {
        cx16.vaddr(1, $c000, 0, 1)
        repeat 64*32 {
            cx16.VERA_DATA0 = 32
            cx16.VERA_DATA0 = $f0
        }
    }

    sub hud_text(ubyte col, ubyte row, ubyte color, uword text_ptr) {
        uword offset = (row as uword) * 128 + col*2
        cx16.vaddr(1, $c000 + offset, 0, 1)
        repeat {
            cx16.r0L = @(text_ptr)
            if_z
                return
            cx16.VERA_DATA0 = cx16.r0L
            cx16.VERA_DATA0 = color
            text_ptr++
        }
    }

    sub hud_wrap_text(ubyte col, ubyte row, ubyte color, uword text_ptr) {
        repeat {
            uword offset = (row as uword) * 128 + col*2
            cx16.vaddr(1, $c000 + offset, 0, 1)
            repeat {
                cx16.r0L = @(text_ptr)
                if_z
                    return
                if cx16.r0L=='|'
                    break
                cx16.VERA_DATA0 = cx16.r0L
                cx16.VERA_DATA0 = color
                text_ptr++
            }
            text_ptr++
            row++
        }
    }

    sub hud_update() {
        const ubyte xpos = 8
        screen.hud_text(xpos+1, 1, $f0, "d")
        conv.str_ub0(cave.num_diamonds)
        screen.hud_text(xpos+3, 1, $f0, conv.string_out)
        screen.hud_text(xpos+6, 1, $f0, "/")
        conv.str_ub0(cave.diamonds_needed)
        screen.hud_text(xpos+7, 1, $f0, conv.string_out)
        screen.hud_text(xpos+12, 1, $f0, "l")
        conv.str_ub0(cave.num_lives)
        screen.hud_text(xpos+14, 1, $f0, conv.string_out)
        screen.hud_text(xpos+19, 1, $f0, "t")
        conv.str_ub0(cave.time_left_secs)
        screen.hud_text(xpos+21, 1, $f0, conv.string_out)
        conv.str_uw0(cave.score)
        screen.hud_text(xpos+26, 1, $f0, conv.string_out)
    }

    sub show_cave_title() {
        const ubyte xpos = 3
        const ubyte ypos = 8
        screen.hud_text(xpos+4, ypos, $f0, "cave:")
        screen.hud_text(xpos+10, ypos, $f0, cave.name_ptr)
        screen.hud_wrap_text(xpos, ypos+5, $f0, cave.description_ptr)
    }

    bool white_flash
    ubyte[16*4] palette_save

    sub flash_white(bool white) {
        white_flash = white
        ubyte idx=0
        uword pal = $fa00
        if white {
            repeat 16 {
                palette_save[idx] = cx16.vpeek(1,pal)
                idx++
                cx16.vpoke(1,pal,$ff)
                pal++
                palette_save[idx] = cx16.vpeek(1,pal)
                idx++
                cx16.vpoke(1,pal,$0f)
                pal++
                palette_save[idx] = cx16.vpeek(1,pal)
                idx++
                cx16.vpoke(1,pal,$ff)
                pal++
                palette_save[idx] = cx16.vpeek(1,pal)
                idx++
                cx16.vpoke(1,pal,$0f)
                pal+=29
            }
        } else {
            repeat 16 {
                cx16.vpoke(1,pal,palette_save[idx])
                idx++
                pal++
                cx16.vpoke(1,pal,palette_save[idx])
                idx++
                pal++
                cx16.vpoke(1,pal,palette_save[idx])
                idx++
                pal++
                cx16.vpoke(1,pal,palette_save[idx])
                idx++
                pal+=29
            }
        }
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
            cx16.save_vera_context()
            ; soft-scrolling is handled in the irq handler itself to avoid stutters
            scroll_screen()
            music.update()
            cave.do_each_frame()    ; for timing critical stuff
            cx16.restore_vera_context()
            psg.envelopes_irq()     ; note: does its own vera save/restore context
        }
    }

    sub scroll_screen() {
        ; smooth scroll the cave layer to top left pixel at sx, sy
        cx16.VERA_L0_HSCROLL_H = msb(screen.scrollx)
        cx16.VERA_L0_HSCROLL_L = lsb(screen.scrollx)
        cx16.VERA_L0_VSCROLL_H = msb(screen.scrolly)
        cx16.VERA_L0_VSCROLL_L = lsb(screen.scrolly)
    }
}

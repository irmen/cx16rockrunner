%import conv
%import diskio
%import psg
%import palette
%import objects
%import cave
%import bd1demo
%import bdcff
%import sounds
%import highscore

main {
    ubyte joystick = 0
    ubyte chosen_level
    ubyte chosen_difficulty
    ubyte game_state
    bool demo_requested

    str BD1_CAVESET_FILE = "boulderdash01.bd"
    const ubyte STATE_CAVETITLE = 1
    const ubyte STATE_CHOOSE_LEVEL = 2
    const ubyte STATE_UNCOVERING = 3
    const ubyte STATE_PLAYING = 4
    const ubyte STATE_GAMEOVER = 5
    const ubyte STATE_DEMO = 6
    const ubyte STATE_SHOWING_HISCORE = 7
    const ubyte STATE_ENTER_NAME = 8
    const ubyte STATE_SELECT_CAVESET = 9
    const uword HISCORE_WAIT_TIME = 60 * 12
    const uword HISCORE_DISPLAY_TIME = 60 * 6
    const uword INSTRUCTIONS_DISPLAY_TIME = 60 * 10
    const uword DEMO_WAIT_TIME = 60 * 21 - HISCORE_DISPLAY_TIME

    sub start() {
;        repeat {
;            ubyte k = cbm.GETIN()
;            if k {
;                txt.print_ub(k)
;                txt.spc()
;            }
;        }

        interrupts.ram_bank = cx16.getrambank()
        music.init()
        screen.titlescreen()
        sys.set_irq(&interrupts.handler, true)
        music.playback_enabled = true

        if not bdcff.load_caveset("0-test.bd") or not bdcff.parse_caveset() {
            ; caveset load error
            error_abort($80)
        }

        sys.wait(200)
        cave.init()
        highscore.load(bdcff.caveset_filename)
        screen.set_tiles_screenmode()
        screen.disable()
        screen.load_tiles()
        activate_choose_level()
        screen.enable()
        ubyte title_timer
        uword start_demo_timer = DEMO_WAIT_TIME
        uword start_hiscore_timer = HISCORE_WAIT_TIME
        uword display_hiscore_timer

        repeat {
            ; the game loop, executed every frame.
            interrupts.waitvsync()
            screen.update()

            when game_state {
                STATE_CHOOSE_LEVEL -> {
                    choose_level()
                    start_demo_timer--
                    if start_demo_timer==0 {
                        start_demo_timer = DEMO_WAIT_TIME
                        if bdcff.caveset_filename == BD1_CAVESET_FILE
                            play_demo()
                    }
                    start_hiscore_timer--
                    if start_hiscore_timer==0 {
                        start_hiscore_timer = HISCORE_WAIT_TIME
                        show_hiscore()
                    }
                }
                STATE_CAVETITLE -> {
                    title_timer--
                    if_z {
                        cx16.r0 = (math.rnd() % (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)) * $0010
                        cx16.r1 = (math.rnd() % (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)) * $0010
                        screen.set_scroll_pos(cx16.r0, cx16.r1)
                        screen.hud_clear()
                        if demo_requested {
                            screen.hud_text(9,10,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88")
                            screen.hud_text(9,11,"\x8e                    \x8d")
                            screen.hud_text(9,12,"\x8d    Rock  Runner    \x8e")
                            screen.hud_text(9,13,"\x8e                    \x8d")
                            screen.hud_text(9,14,"\x8d       Demo !       \x8e")
                            screen.hud_text(9,15,"\x8e                    \x8d")
                            screen.hud_text(9,16,"\x8d press ESC to abort \x8e")
                            screen.hud_text(9,17,"\x8e                    \x8d")
                            screen.hud_text(9,18,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88")
                        }
                        music.playback_enabled = false
                        game_state = STATE_UNCOVERING
                    }
                }
                STATE_UNCOVERING -> {
                    cave.uncover_more()
                    if not cave.covered {
                        cave.scroll_enabled = cave.width>cave.VISIBLE_CELLS_H or cave.height>cave.VISIBLE_CELLS_V
                        if demo_requested
                            game_state = STATE_DEMO
                        else
                            game_state = STATE_PLAYING
                    }
                }
                STATE_PLAYING -> {
                    ubyte action = cave.scan()
                    if interrupts.vsync_counter % 3 == 0
                        screen.hud_update()
                    when action {
                        cave.ACTION_GAMEOVER -> game_state = STATE_GAMEOVER
                        cave.ACTION_RESTARTLEVEL -> {
                            if cave.intermission {
                                ; intermissions are bonus levels and you have only one try at them
                                next_level()
                            } else {
                                bdcff.parse_cave(chosen_level, chosen_difficulty)
                                cave.cover_all()
                                cave.restart_level()
                                game_state = STATE_UNCOVERING
                            }
                        }
                        cave.ACTION_NEXTLEVEL -> {
                            next_level()
                        }
                    }
                }
                STATE_DEMO -> {
                    if cave.scan() != cave.ACTION_NOTHING {
                        activate_choose_level()
                    }
                }
                STATE_SHOWING_HISCORE -> {
                    display_hiscore_timer--
                    if display_hiscore_timer==0 or cbm.GETIN()==27 {
                        activate_choose_level()
                    }
                }
                STATE_GAMEOVER -> {
                    if highscore.highscore_pos(cave.score)
                        activate_highscore_enter_name()
                    else
                        show_hiscore()
                }
                STATE_ENTER_NAME -> {
                    if highscore.enter_name() {
                        highscore.record_score(bdcff.caveset_filename, cave.score, highscore.name_input)
                        show_hiscore()
                    } else
                        screen.hud_text(24,14,highscore.name_input)
                }
                STATE_SELECT_CAVESET -> {
                    select_caveset()
                }
            }
        }
    }

    sub error_abort(ubyte errorcode) {
        ; stores the error code at $0400 so you can tell what it was after the reset.
        @($0400) = errorcode
        %asm {{
            brk
        }}
        sys.reset_system()
    }

    sub next_level() {
        chosen_level++
        if chosen_level > bdcff.num_caves {
            chosen_level = 1
            chosen_difficulty = min(5, chosen_difficulty+1)
        }
        bdcff.parse_cave(chosen_level, chosen_difficulty)
        start_loaded_level()
    }

    sub activate_choose_level() {
        chosen_difficulty = 1
        chosen_level = 1
        main.choose_level.update_hud_choices_text()
        demo_requested = false
        screen.hud_clear()
        cave.cover_all()
        if not music.playback_enabled {
            music.init()
            music.playback_enabled = true
        }
        while cbm.GETIN() {
            ; clear any remaining keypresses
        }
        game_state = STATE_CHOOSE_LEVEL
    }

    sub choose_level() {
        ubyte letter
        bool joy_start = false
        for letter in 0 to 4 {
            ; any joystick START button will select that joystick and start the game
            if cx16.joystick_get2(letter) & %0000000000010000 == 0 {
                main.joystick = letter
                joy_start = true
                break
            }
        }
        str cave_letter_str     = "A-T: select start cave [A]"
        str cave_difficulty_str = "1-5: select difficulty [1]"
        letter = cbm.GETIN()
        if letter!=0 {
            main.start.start_demo_timer = DEMO_WAIT_TIME
            main.start.start_hiscore_timer = HISCORE_WAIT_TIME
        }
        if cx16.joystick_get2(4) & %0000000000010000 == 0 {
            main.joystick = 4
            joy_start = true
        }
        if letter==13 or joy_start {
            ; start the game!
            bdcff.parse_cave(chosen_level, chosen_difficulty)
            start_new_game()
            start_loaded_level()
            return
        }
        else if letter>='a' and letter <= 't' {
            ; letter - select start cave
            chosen_level = letter - 'a' + 1
            update_hud_choices_text()
            bdcff.parse_cave(chosen_level, chosen_difficulty)
            cave.cover_all()
            screen.hud_clear()
            screen.show_cave_title(false)
            while cbm.GETIN() {
                ; clear any remaining keypresses
            }
        }
        else if letter>='1' and letter <= '5' {
            ; digit - select difficulty
            chosen_difficulty = letter-'0'
            update_hud_choices_text()
        }
        else if letter==133 {
            ; F1 - load different caveset
            activate_select_caveset('*')
            return
        }
        else if letter==137 {
            ; F2 - play demo
            play_demo()
            return
        }
        else if letter==134 {
            ; F3 - hall of fame
            show_hiscore()
            return
        }
        else if letter==138 {
            ; F4 - instructions
            show_instructions()
            return
        }
        screen.hud_text(4,2,"\x8e\x8e\x8e Rock Runner BETA VERSION \x8e\x8e\x8e")
        screen.hud_text(4,4,"by DesertFish. Written in Prog8")

        ; what caveset is loaded
        screen.hud_text(4,6,"Caveset: ")
        screen.hud_text(13, 6, bdcff.caveset_filename)
        screen.hud_text(6, 7, bdcff.caveset_name)
        screen.hud_text(6, 8, bdcff.caveset_author)

        ; menu
        screen.hud_text(7,19,cave_letter_str)
        screen.hud_text(7,20,cave_difficulty_str)
        screen.hud_text(8,21,"F1: load different caveset")
        screen.hud_text(8,22,"F2: play demo (BD1 cave A)")
        screen.hud_text(8,23,"F3: show hall of fame")
        screen.hud_text(8,24,"F4: instructions")
        screen.hud_text(7,26,"Any joystick START button")
        screen.hud_text(10,27,"to start the game!")

        sub update_hud_choices_text() {
            cave_letter_str[len(cave_letter_str)-2] = chosen_level+'A'-1
            cave_difficulty_str[len(cave_difficulty_str)-2] = chosen_difficulty+'0'
        }
    }


    sub start_new_game() {
        cave.num_lives = 3
        cave.score = 0
        cave.score_500_for_bonus = 0
    }

    sub start_loaded_level() {
        cave.cover_all()
        cave.restart_level()
        main.start.title_timer = 250
        game_state = STATE_CAVETITLE
        screen.hud_clear()
        screen.show_cave_title(true)
    }

    sub play_demo() {
        if bdcff.caveset_filename != BD1_CAVESET_FILE {
            ; demo only works on boulderdash 1 cave 1
            if not bdcff.load_caveset(BD1_CAVESET_FILE) or not bdcff.parse_caveset() {
                ; caveset load error
                error_abort($81)
            }
            highscore.load(BD1_CAVESET_FILE)
        }
        chosen_level = 1
        bdcff.parse_cave(1, chosen_difficulty)
        bd1demo.init()
        start_loaded_level()
        demo_requested = true
        main.start.title_timer = 1
    }

    sub show_instructions() {
        game_state = STATE_SHOWING_HISCORE
        main.start.display_hiscore_timer = INSTRUCTIONS_DISPLAY_TIME
        screen.hud_clear()
        screen.hud_text(7,3,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        screen.hud_text(7,5,"Rock Runner  Instructions")
        screen.hud_text(7,7,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        screen.hud_text(4,11,"Pick up enough diamonds in the")
        screen.hud_text(4,12,"cave to unlock the exit, and")
        screen.hud_text(4,13,"reach it before the time runs out.")
        screen.hud_text(4,14,"Avoid enemies and getting crushed.")
        screen.hud_text(4,17,"Control the game using any joypad")
        screen.hud_text(4,18,"(start button activates).")
        screen.hud_text(4,19,"Fire+direction lets you grab")
        screen.hud_text(4,20,"something without moving there!")
        screen.hud_text(4,23,"Press ESC when you're stuck.")

    }

    str caveset_prefix = "**"
    ubyte caveset_selected_index
    const ubyte CAVESET_DISPLAYLIST_MAXLENGTH = 20
    ubyte caveset_filenames_amount

    sub activate_select_caveset(ubyte prefixletter) {
        ; $81 = down, $82 = left, $83 = up, $84 = right arrows.
        game_state = STATE_SELECT_CAVESET
        screen.hud_clear()
        screen.hud_text(3,2,"Select a caveset from the list")
        screen.hud_text(3,3,"(scanned from the 'caves' subdir)")
        screen.hud_text(3,4,"Press letter or digit or '*' to use")
        screen.hud_text(3,5,"that as a name prefix filter.")
        diskio.chdir("caves")
        caveset_prefix[0] = prefixletter
        cx16.rambank(bdcff.FILENAMES_BANK)
        caveset_filenames_amount = diskio.list_filenames(caveset_prefix, $a000, $2000)
        diskio.chdir("..")
        ubyte row = 0
        uword name_ptr = $a000
        cx16.rambank(bdcff.FILENAMES_BANK)
        screen.hud_text(5, 8, "\x83")
        screen.hud_text(5, 27, "\x81")
        while row < CAVESET_DISPLAYLIST_MAXLENGTH and row < caveset_filenames_amount {
            screen.hud_text(12, row+8, name_ptr)
            row++
            while @(name_ptr)
                name_ptr++
            name_ptr++
        }
        caveset_selected_index = 0
        screen.hud_text(9, 8, "\x84")       ; right arrow on the first entry
    }

    sub select_caveset() {
        cx16.r0L = cbm.GETIN()
        cx16.r1L = string.lowerchar(cx16.r0L)
        if cx16.r1L>32 and cx16.r1L<='z' {
            activate_select_caveset(cx16.r0L)
            while cbm.GETIN() {
                ; clear buffer
            }
        } else {
            when cx16.r0L {
                27 -> activate_choose_level()
                13 -> {
                    if caveset_selected_index < caveset_filenames_amount {
                        uword name_ptr = $a000
                        cx16.rambank(bdcff.FILENAMES_BANK)
                        ubyte row=0
                        repeat {
                            if row==caveset_selected_index {
                                if not bdcff.load_caveset(name_ptr) or not bdcff.parse_caveset() {
                                    ; caveset load error
                                    error_abort($84)
                                }
                                highscore.load(bdcff.caveset_filename)
                                sys.wait(10)
                                activate_choose_level()
                                return
                            }
                            row++
                            while @(name_ptr)
                                name_ptr++
                            name_ptr++
                        }
                    }
                }
                145 -> {
                    if caveset_selected_index>0 {
                        ; up
                        screen.hud_text(9, caveset_selected_index+8, " ")
                        caveset_selected_index--
                        screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                    }
                }
                17 -> {
                    if caveset_selected_index<CAVESET_DISPLAYLIST_MAXLENGTH-1 {
                        ; down
                        screen.hud_text(9, caveset_selected_index+8, " ")
                        caveset_selected_index++
                        screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                    }
                }
            }
            ; TODO scroll the filename list if there are more names than that can fit on the screen
            ; TODO also allow joypad for file selection
        }
    }

    sub show_hiscore() {
        game_state = STATE_SHOWING_HISCORE
        main.start.display_hiscore_timer = HISCORE_DISPLAY_TIME
        screen.hud_clear()
        screen.hud_text(7,3,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        screen.hud_text(7,5,"Rock Runner  Hall Of Fame")
        screen.hud_text(7,6,"Caveset: ")
        screen.hud_text(16, 6, bdcff.caveset_filename)
        screen.hud_text(10, 7, bdcff.caveset_name)
        screen.hud_text(7,9,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        ubyte position
        str position_str = "?."
        for position in 0 to 7 {
            position_str[0] = '1'+position
            screen.hud_text(10, 11+position*2, position_str)
            screen.hud_text(14, 11+position*2, highscore.get_name(position))
            conv.str_uw0(highscore.get_score(position))
            for cx16.r0L in 0 to 7 {
                if conv.string_out[cx16.r0L] != '0'
                    break
                conv.string_out[cx16.r0L] = ' '
            }
            screen.hud_text(24, 11+position*2, conv.string_out)
        }
    }

    sub activate_highscore_enter_name() {
        game_state = STATE_ENTER_NAME
        music.init()
        music.playback_enabled = true
        screen.hud_clear()
        screen.hud_text(7,10,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        screen.hud_text(7,12,"You got a new High Score!")
        screen.hud_text(7,14,"Enter your name:")
        screen.hud_text(7,16,"\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d")
        highscore.start_enter_name()
        ; name entry is handled in a separate subroutine!
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
        if cave.scroll_enabled
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
        scrollx = clamp(scrollx, 0, (cave.MAX_CAVE_WIDTH-cave.VISIBLE_CELLS_H)*16 as word)
        scrolly = clamp(scrolly, 0, (cave.MAX_CAVE_HEIGHT-cave.VISIBLE_CELLS_V)*16)
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

        void diskio.vload_raw("titlescreen.bin", 0, $0000)
        void diskio.vload_raw("titlescreen.pal", 1, $fa00)
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO | %00010000       ; layer 0 active
    }

    sub load_tiles() {
        void diskio.vload_raw("tiles.bin", 0, $0000)
        void diskio.vload_raw("tiles.pal", 1, $fa00)
        void diskio.vload_raw("font.bin", 1, $e000)
        ; fixup the palette for the HUD text font (entries $f0-$ff)
        cx16.vpoke(1,$fa00+$f0*2,$00)
        cx16.vpoke(1,$fa00+$f0*2+1,$00)
        cx16.vpoke(1,$fa00+$f1*2,$24)
        cx16.vpoke(1,$fa00+$f1*2+1,$05)
        cx16.vpoke(1,$fa00+$f2*2,$ff)
        cx16.vpoke(1,$fa00+$f2*2+1,$0f)
        cx16.vpoke(1,$fa00+$f2*3,$f0)
        cx16.vpoke(1,$fa00+$f2*3+1,$ff)

        void diskio.vload_raw("bgsprite.bin", 1, $f000)
        void diskio.vload_raw("bgsprite.pal", 1, $fa00+14*16*2)
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

        ; background sprite layer: repeat a big sprite a couple of times across the background.
        cx16.vaddr(1, $fc00, 0, true)
        ubyte spr_ypos = 0
        repeat 4 {
            ubyte spr_xpos = 8
            repeat 4 {
                cx16.VERA_DATA0 = lsb($1f000 >> 5)
                cx16.VERA_DATA0 = lsb($1f000 >> 13)
                cx16.VERA_DATA0 = spr_xpos
                cx16.VERA_DATA0 = 0
                cx16.VERA_DATA0 = spr_ypos
                cx16.VERA_DATA0 = 0
                cx16.VERA_DATA0 = %00000100
                cx16.VERA_DATA0 = %11110000 | 14
                spr_xpos += 80
                spr_ypos += 8
            }
            spr_ypos += 80-32
        }

        cx16.VERA_CTRL = 0
        cx16.VERA_DC_BORDER = 0
        cx16.VERA_DC_VIDEO = cx16.VERA_DC_VIDEO & $0f | %01110000       ; layer 0 and 1 active, and sprites
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

    sub hud_text(ubyte col, ubyte row, uword text_ptr) {
        uword offset = (row as uword) * 128 + col*2
        cx16.vaddr(1, $c000 + offset, 0, 1)
        repeat {
            cx16.r0L = @(text_ptr)
            if_z
                return
            cx16.VERA_DATA0 = cx16.r0L
            cx16.VERA_DATA0 = $f0  ; 'color'
            text_ptr++
        }
    }

    sub hud_wrap_text(ubyte col, ubyte row, ubyte maxwidth, uword text_ptr) {
        ubyte line_width
        row--
        new_line()
        repeat {
            ubyte word_length = next_word_length(text_ptr)
            if_z
                return
            repeat word_length {
                cx16.VERA_DATA0 = @(text_ptr)
                cx16.VERA_DATA0 = $f0 ; 'color'
                text_ptr++
                line_width++
            }
            cx16.VERA_DATA0 = ' '
            cx16.VERA_DATA0 = $f0 ; 'color'
            line_width++

            if @(text_ptr)==0
                return
            text_ptr++

            if line_width>maxwidth
                new_line()
        }

        sub new_line() {
            row++
            uword offset = (row as uword) * 128 + col*2
            cx16.vaddr(1, $c000 + offset, 0, 1)
            line_width = 0
        }

        sub next_word_length(uword txt) -> ubyte {
            ubyte length=0
            repeat {
                if @(txt)==0 or @(txt)==' '
                    return length
                length++
                txt++
            }
        }
    }

    sub hud_update() {
        const ubyte xpos = 8
        screen.hud_text(xpos+1, 1, "\x8e")     ; diamond symbol
        conv.str_ub0(cave.num_diamonds)
        screen.hud_text(xpos+3, 1, conv.string_out)
        screen.hud_text(xpos+6, 1, "/")
        conv.str_ub0(cave.diamonds_needed)
        screen.hud_text(xpos+7, 1, conv.string_out)
        screen.hud_text(xpos+12, 1, "\x88")       ; rockford symbol
        conv.str_ub0(cave.num_lives)
        screen.hud_text(xpos+14, 1, conv.string_out)
        screen.hud_text(xpos+19, 1, "\x8f")     ; clock symbol
        conv.str_ub0(cave.time_left_secs)
        screen.hud_text(xpos+21, 1, conv.string_out)
        conv.str_uw0(cave.score)
        screen.hud_text(xpos+26, 1, conv.string_out)
    }

    sub show_cave_title(bool with_description) {
        const ubyte xpos = 3
        const ubyte ypos = 11
        screen.hud_text(xpos+4, ypos, "cave:")
        screen.hud_text(xpos+10, ypos, cave.name)
        if with_description
            screen.hud_wrap_text(xpos, ypos+3, 25, cave.description)
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
    ubyte ram_bank
    ubyte ram_bank_backup

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

        ; Quoted from the documentation:
        ; " The speed of play is implemented with a delay loop. Each frame, if the CaveDelay is greater than zero,
        ; BoulderDash enters a time-delay loop for 90 cycles per unit of CaveDelay (remembering that the C64 runs at 1 MHz).
        ; The actual number of frames per second will vary depending on the objects in the cave;
        ; a cave full of boulders takes longer to process than a cave full of dirt.
        ;        Difficulty 1: CaveDelay = 12 (1080 cycles)
        ;        Difficulty 2: CaveDelay = 6 (540 cycles)
        ;        Difficulty 3: CaveDelay = 3 (270 cycles)
        ;        Difficulty 4: CaveDelay = 1 (90 cycles)
        ;        Difficulty 5: CaveDelay = 0 (no delay)  "
        ; Now, this is al very difficult to translate to the X16:
        ;  - it runs at 8 mhz not 1 mhz
        ;  - the time to process a cave is wildly different from the original game because it's totally different code
        ;  - it has 60hz refresh mode rather than 50hz (PAL c64)
        ; So what I've chosen to do is not to implement this "Cave Delay" and rather make cave_speed
        ; (the number of frames between cave scans) lower for higher difficulty levels.

        if cx16.VERA_ISR & %00000001 {
            ram_bank_backup = cx16.getrambank()
            cx16.rambank(ram_bank)       ; make sure we see the correct ram bank
            cx16.save_virtual_registers()
            vsync_semaphore=0
            vsync_counter++
            cx16.save_vera_context()
            set_softscroll()             ; soft-scrolling is handled in this irq handler itself to avoid stutters and tearing
            music.update()
            cave.do_each_frame()         ; for timing critical stuff
            cx16.restore_vera_context()
            psg.envelopes_irq()          ; note: does its own vera save/restore context
            cx16.rambank(ram_bank_backup)
            cx16.restore_virtual_registers()
        }
    }

    sub set_softscroll() {
        ; smooth scroll the cave layer to top left pixel at sx, sy
        cx16.VERA_L0_HSCROLL_H = msb(screen.scrollx)
        cx16.VERA_L0_HSCROLL_L = lsb(screen.scrollx)
        cx16.VERA_L0_VSCROLL_H = msb(screen.scrolly)
        cx16.VERA_L0_VSCROLL_L = lsb(screen.scrolly)
    }
}

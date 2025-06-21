%import conv
%import diskio
%import psg
%import screen
%import cave
%import bd1demo
%import bdcff
%import highscore
%import cavesets


main {
    ubyte chosen_level
    ubyte chosen_difficulty
    ubyte game_state
    ubyte tileset = 2
    bool demo_requested

    str BD1_CAVESET_FILE = "1-boulderdash01.bd"
    const ubyte STATE_CAVETITLE = 1
    const ubyte STATE_TITLE_MENU = 2
    const ubyte STATE_UNCOVERING = 3
    const ubyte STATE_PLAYING = 4
    const ubyte STATE_GAMEOVER = 5
    const ubyte STATE_DEMO = 6
    const ubyte STATE_SHOWING_HISCORE = 7
    const ubyte STATE_ENTER_NAME = 8
    const ubyte STATE_SELECT_CAVESET = 9
    const ubyte STATE_SELECT_TILESET = 10
    const uword HISCORE_WAIT_TIME = 60 * 12
    const uword HISCORE_DISPLAY_TIME = 60 * 6
    const uword INSTRUCTIONS_DISPLAY_TIME = 60 * 10
    const uword DEMO_WAIT_TIME = 60 * 21 - HISCORE_DISPLAY_TIME

    const bool quicklaunch_mode = false           ; set to TRUE to quickly enter game (loads 3-test.bd caveset)
    const ubyte quicklaunch_start_cave = 'b'
    const ubyte quicklaunch_joystick = 0
    const ubyte quicklaunch_cavespeed = 8


    sub start() {
        clear_abort_error()
        joystick.active_joystick = 0
        interrupts.ram_bank = cx16.getrambank()
        music.init()
        if not quicklaunch_mode
            screen.titlescreen()
        sys.set_irq(&interrupts.handler)
        music.playback_enabled = not quicklaunch_mode

        if quicklaunch_mode {
            void cavesets.load_caveset("3-test.bd")
            void bdcff.parse_caveset()
        } else {
            if not cavesets.load_caveset(BD1_CAVESET_FILE) or not bdcff.parse_caveset() {
                ; caveset load error
                error_abort($80)
            }
            sys.wait(200)
        }

        cave.init()
        highscore.load(cavesets.caveset_filename)
        screen.set_tiles_screenmode()
        screen.disable()
        screen.load_tiles(tileset)
        activate_title_menu_state(true)
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
                STATE_TITLE_MENU -> {
                    choose_level()
                    start_demo_timer--
                    if start_demo_timer==0 {
                        start_demo_timer = DEMO_WAIT_TIME
                        if cavesets.caveset_filename == BD1_CAVESET_FILE
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
                        screen.set_scroll_pos(0, 0)     ; not random?
                        screen.hud_clear()
                        if demo_requested {
                            uword[] @nosplit announcement = [
                                mkword(9, 10), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88",
                                mkword(9, 11), "\x8e                    \x8d",
                                mkword(9, 12), "\x8d    Rock  Runner    \x8e",
                                mkword(9, 13), "\x8e                    \x8d",
                                mkword(9, 14), "\x8d       Demo !       \x8e",
                                mkword(9, 15), "\x8e                    \x8d",
                                mkword(9, 16), "\x8d press ESC to abort \x8e",
                                mkword(9, 17), "\x8e                    \x8d",
                                mkword(9, 18), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88"
                            ]
                            screen.hud_texts(announcement, len(announcement)/2)
                        }
                        music.playback_enabled = false
                        game_state = STATE_UNCOVERING
                    }
                }
                STATE_UNCOVERING -> {
                    if quicklaunch_mode
                        cave.uncover_all()
                    cave.uncover_more()
                    if not cave.covered {
                        while cbm.GETIN2()!=0 { /* clear keyboard buffer */ }
                        cave.scroll_enabled = cave.width>cave.VISIBLE_CELLS_H or cave.height>cave.VISIBLE_CELLS_V
                        interrupts.cavescan_frame = 0
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
                        activate_title_menu_state(true)
                    }
                }
                STATE_SHOWING_HISCORE -> {
                    display_hiscore_timer--
                    if display_hiscore_timer==0 or cbm.GETIN2()==27 {
                        activate_title_menu_state(false)
                    }
                }
                STATE_GAMEOVER -> {
                    if highscore.highscore_pos(cave.score)!=0
                        activate_highscore_enter_name()
                    else
                        show_hiscore()
                }
                STATE_ENTER_NAME -> {
                    if highscore.enter_name() {
                        highscore.record_score(cavesets.caveset_filename, cave.score, highscore.name_input)
                        show_hiscore()
                    } else
                        screen.hud_text(24,14,highscore.name_input)
                }
                STATE_SELECT_CAVESET -> {
                    select_caveset()
                }
                STATE_SELECT_TILESET -> {
                    select_tileset()
                }
            }
        }
    }

    sub clear_abort_error() {
        ; make sure no error value is stored initially
        @($0400) = 0
        @($0401) = 0
    }

    sub error_abort(ubyte errorcode) {
        ; stores the error code at $0400 and $0401 so you can tell what it was after the monitor brk or reset.
        @($0400) = errorcode
        @($0401) = errorcode
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

    sub activate_title_menu_state(bool reset_chosen_level) {
        game_state = STATE_TITLE_MENU
        if reset_chosen_level {
            chosen_difficulty = 1
            chosen_level = 1
        }
        main.choose_level.update_hud_choices_text()
        demo_requested = false
        screen.hud_clear()
        screen.show_logo_image(false)
        cave.cover_all()
        screen.dim_covertile_color(true)
        if not music.playback_enabled {
            music.init()
            music.playback_enabled = true
        }
        while cbm.GETIN2()!=0 { /* clear keyboard buffer */ }
    }

    sub choose_level() {
        ubyte letter
        bool joy_start = false
        for joystick.active_joystick in 0 to 4 {
            joystick.scan()
            if joystick.start {
                joy_start = true
                break
            }
        }

        str cave_and_level_select_str = "A-T: start cave=A  1-5: difficulty=1"
        letter = cbm.GETIN2()

        if quicklaunch_mode
            letter = quicklaunch_start_cave

        if letter!=0 {
            main.start.start_demo_timer = DEMO_WAIT_TIME
            main.start.start_hiscore_timer = HISCORE_WAIT_TIME
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
            cx16.r0L = letter - 'a' + 1
            if cx16.r0L <= bdcff.num_caves {
                chosen_level = cx16.r0L
                update_hud_choices_text()
                bdcff.parse_cave(chosen_level, chosen_difficulty)
                cave.cover_all()
                screen.hud_clear()
                ; Don't show the cave title anymore it falls below the game's logo graphics.
                ; screen.show_cave_title(false)
                if quicklaunch_mode {
                    start_new_game()
                    start_loaded_level()
                    joystick.active_joystick=quicklaunch_joystick
                    cave.cave_speed = quicklaunch_cavespeed
                    return
                }
            }
            while cbm.GETIN2()!=0 { /* clear keyboard buffer */ }
        }
        else if letter>='1' and letter <= '5' {
            ; digit - select difficulty
            cx16.r0L = letter-'0'
            if cx16.r0L <= bdcff.num_difficulty_levels {
                chosen_difficulty = cx16.r0L
                update_hud_choices_text()
            }
        }
        else if letter==133 {
            ; F1 - load different caveset
            activate_select_caveset()
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
        else if letter==135 {
            ; F5 - select tile set
            activate_select_tileset()
            return
        }

        uword[] @nosplit texts = [
            mkword(4,2), "\x8e\x8e\x8e\x8e   Rock  Runner  v1.4b  \x8e\x8e\x8e\x8e",        ; VERSION NUMBER is here
            mkword(4,4), "by DesertFish. Written in Prog8",
            mkword(4,15), "Caveset: ",
            ; what caveset is loaded:
            mkword(13,15), cavesets.caveset_filename,
            mkword(6,16), bdcff.caveset_name,
            mkword(6,17), bdcff.caveset_author,
            ; menu
            mkword(8,19), "F1: load different caveset",
            mkword(8,20), "F2: play demo (BD1 cave A)",
            mkword(8,21), "F3: show hall of fame",
            mkword(8,22), "F4: instructions",
            mkword(8,23), "F5: choose tile graphics",
            mkword(2,25), cave_and_level_select_str,
            mkword(7,26), "Any joystick START button",
            mkword(10,27), "to start the game!"
        ]

        screen.hud_texts(texts, len(texts)/2)

        ; logo
        screen.show_logo_image(true)

        sub update_hud_choices_text() {
            cave_and_level_select_str[16] = chosen_level+'A'-1
            cave_and_level_select_str[35] = chosen_difficulty+'0'
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
        if quicklaunch_mode
            main.start.title_timer = 60
        game_state = STATE_CAVETITLE
        screen.hud_clear()
        screen.show_logo_image(false)
        screen.show_cave_title(true)
        screen.show_background_sprite_layer()
        screen.dim_covertile_color(false)
    }

    sub play_demo() {
        if cavesets.caveset_filename != BD1_CAVESET_FILE {
            ; demo only works on boulderdash 1 cave 1
            if not cavesets.load_caveset(BD1_CAVESET_FILE) or not bdcff.parse_caveset() {
                ; caveset load error
                error_abort($81)
            }
            highscore.load(BD1_CAVESET_FILE)
        }
        chosen_level = 1
        chosen_difficulty = 1
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
        screen.show_logo_image(false)

        uword[] @nosplit instructions = [
            mkword(7,3), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d",
            mkword(7,5), "Rock Runner  Instructions",
            mkword(7,7), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d",
            mkword(4,11), "Pick up enough diamonds in the",
            mkword(4,12), "cave to unlock the exit, and",
            mkword(4,13), "reach it before the time runs out.",
            mkword(4,14), "Avoid enemies and getting crushed.",
            mkword(4,17), "Control the game using any joypad",
            mkword(4,18), "(start button activates).",
            mkword(4,19), "Fire+direction lets you grab",
            mkword(4,20), "something without moving there!",
            mkword(4,23), "Press ESC when you're stuck: this",
            mkword(4,24), "restarts the level (losing a life)"
        ]

        screen.hud_texts(instructions, len(instructions)/2)
    }

    sub activate_select_tileset() {
        game_state = STATE_SELECT_TILESET
        screen.hud_clear()
        screen.show_logo_image(false)

        uword[] @nosplit instructions = [
            mkword(4,5), "Choose the Graphics Tile Set:",
            mkword(10,9), "1 - classic",
            mkword(10,11), "2 - new",
            mkword(4,19), "classic tiles from Boulder Rush",
            mkword(4,20), "new tiles by Shign Bright"
        ]

        screen.hud_texts(instructions, len(instructions)/2)

        str chosen = "currently loaded: ?"
        chosen[len(chosen)-1] = tileset+'0'
        screen.hud_text(8, 14, chosen)
    }

    ubyte caveset_selected_index
    ubyte caveset_selected_page
    const ubyte CAVESET_DISPLAYLIST_MAXLENGTH = 20
    ubyte caveset_filenames_amount

    sub activate_select_caveset() {
        ; $81 = down, $82 = left, $83 = up, $84 = right arrows.
        game_state = STATE_SELECT_CAVESET
        screen.hud_clear()
        screen.show_logo_image(false)

        uword[] @nosplit instructions = [
            mkword(3,2), "Select a caveset from the list",
            mkword(3,3), "(scanned from the 'caves' subdir)",
            mkword(3,4), "Enter/start/fire confirms caveset.",
            mkword(3,5), "Keep scrolling for more pages."
        ]
        screen.hud_texts(instructions, len(instructions)/2)

        caveset_filenames_amount = cavesets.load_filenames()
        caveset_selected_index = caveset_selected_page = 0
        screen.hud_text(5, 13, "\x83")
        screen.hud_text(5, 22, "\x81")
        draw_caveset_file_list(caveset_selected_page)
        screen.hud_text(9, 8, "\x84")       ; right arrow on the first entry
    }

    sub draw_caveset_file_list(ubyte page) {
        ubyte row
        for row in 0 to CAVESET_DISPLAYLIST_MAXLENGTH-1 {
            screen.hud_text(12, row+8, " " * 24)
            screen.hud_text(12, row+8, cavesets.get_filename(row + page * CAVESET_DISPLAYLIST_MAXLENGTH))
        }
    }

    sub select_tileset() {
        ubyte keypress = cbm.GETIN2()
        while cbm.GETIN2()!=0 { /* clear keyboard buffer */ }
        if keypress == '1' {
            tileset = 1
            screen.dim_covertile_color(false)
            screen.load_game_tiles(1)
            screen.dim_covertile_color(true)
            activate_title_menu_state(false)
        }
        else if keypress == '2' {
            tileset = 2
            screen.dim_covertile_color(false)
            screen.load_game_tiles(2)
            screen.dim_covertile_color(true)
            activate_title_menu_state(false)
        }
        return
    }

    sub select_caveset() {
        ubyte keypress = cbm.GETIN2()
        while cbm.GETIN2()!=0 { /* clear keyboard buffer */ }
        if keypress == 27 {
            activate_title_menu_state(false)
            return
        }
        if keypress==0 and interrupts.vsync_counter & 3 !=0
            return
        for joystick.active_joystick in 1 to 4 {        ; skip 0 as it interferes with the normal keys
            joystick.scan()
            if keypress==13 or joystick.start or joystick.fire {
                cx16.r0 = cavesets.get_filename(caveset_selected_index + caveset_selected_page * CAVESET_DISPLAYLIST_MAXLENGTH)
                if cx16.r0 != 0 {
                    if not cavesets.load_caveset(cx16.r0) or not bdcff.parse_caveset() {
                        ; caveset load error
                        error_abort($84)
                    }
                    highscore.load(cavesets.caveset_filename)
                    sys.wait(10)
                    activate_title_menu_state(true)
                }
                return
            }
            if keypress==145 or joystick.up {
                if caveset_selected_index>0 {
                    ; up
                    screen.hud_text(9, caveset_selected_index+8, " ")
                    caveset_selected_index--
                    screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                } else prev_page()
                return
            }
            if keypress==17 or joystick.down {
                if caveset_selected_index<CAVESET_DISPLAYLIST_MAXLENGTH-1 {
                    ; down
                    screen.hud_text(9, caveset_selected_index+8, " ")
                    caveset_selected_index++
                    screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                } else next_page()
                return
            }
        }

        if keypress==130 prev_page()
        if keypress==2 next_page()

        sub prev_page() {
            if caveset_selected_page>0 {
                screen.hud_text(9, caveset_selected_index+8, " ")
                caveset_selected_index = CAVESET_DISPLAYLIST_MAXLENGTH-1
                screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                caveset_selected_page--
                draw_caveset_file_list(caveset_selected_page)
            }
        }

        sub next_page() {
            if (caveset_selected_page+1)*CAVESET_DISPLAYLIST_MAXLENGTH < caveset_filenames_amount {
                caveset_selected_page++
                screen.hud_text(9, caveset_selected_index+8, " ")
                caveset_selected_index = 0
                screen.hud_text(9, caveset_selected_index+8, "\x84")       ; right arrow
                draw_caveset_file_list(caveset_selected_page)
            }
        }
    }

    sub show_hiscore() {
        game_state = STATE_SHOWING_HISCORE
        main.start.display_hiscore_timer = HISCORE_DISPLAY_TIME
        screen.hud_clear()
        screen.show_logo_image(false)

        uword[] @nosplit halltxt = [
            mkword(7,3), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d",
            mkword(7,5), "Rock Runner  Hall Of Fame",
            mkword(7,6), "Caveset: ",
            mkword(16,6), cavesets.caveset_filename,
            mkword(10,7), bdcff.caveset_name,
            mkword(7,9), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d"
        ]
        screen.hud_texts(halltxt, len(halltxt)/2)

        ubyte position
        str position_str = "?."
        for position in 0 to 7 {
            position_str[0] = '1'+position
            screen.hud_text(10, 11+position*2, position_str)
            screen.hud_text(14, 11+position*2, highscore.get_name(position))
            uword score_string = conv.str_uw0(highscore.get_score(position))
            for cx16.r0L in 0 to 7 {
                if score_string[cx16.r0L] != '0'
                    break
                score_string[cx16.r0L] = ' '
            }
            screen.hud_text(24, 11+position*2, score_string)
        }
    }

    sub activate_highscore_enter_name() {
        game_state = STATE_ENTER_NAME
        music.init()
        music.playback_enabled = true
        screen.hud_clear()

        uword [] @nosplit highscore_txts = [
            mkword(7,10), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d",
            mkword(7,12), "You got a new High Score!",
            mkword(7,14), "Enter your name:",
            mkword(7,16), "\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d\x88\x8d"
        ]

        screen.hud_texts(highscore_txts, len(highscore_txts)/2)

        highscore.start_enter_name()
        ; name entry is handled in a separate subroutine!
    }
}

interrupts {
    ubyte vsync_counter = 0
    ubyte cavescan_frame = 0
    ubyte vsync_semaphore = 1
    ubyte ram_bank
    ubyte ram_bank_backup

    asmsub waitvsync() {
        %asm {{
-           wai
            lda  p8v_vsync_semaphore
            bne  -
            inc  p8v_vsync_semaphore
            rts
        }}
    }

    sub handler() -> bool {
        if cx16.VERA_ISR & %00000001 !=0 {
            ram_bank_backup = cx16.getrambank()
            cx16.rambank(ram_bank)       ; make sure we see the correct ram bank
            cx16.save_virtual_registers()
            vsync_semaphore=0
            vsync_counter++
            cavescan_frame++
            cx16.save_vera_context()
            set_softscroll()             ; soft-scrolling is handled in this irq handler itself to avoid stutters and tearing
            music.update()
            cave.do_each_frame()         ; for timing critical stuff
            cx16.restore_vera_context()
            void psg.envelopes_irq()          ; note: does its own vera save/restore context
            cx16.rambank(ram_bank_backup)
            cx16.restore_virtual_registers()
            return true
        }
        return false
    }

    sub set_softscroll() {
        ; smooth scroll the cave layer to top left pixel at sx, sy
        cx16.VERA_L0_HSCROLL_H = msb(screen.scrollx)
        cx16.VERA_L0_HSCROLL_L = lsb(screen.scrollx)
        cx16.VERA_L0_VSCROLL_H = msb(screen.scrolly)
        cx16.VERA_L0_VSCROLL_L = lsb(screen.scrolly)
    }
}

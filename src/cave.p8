%import math

; documentation about object behaviors:
; https://codeincomplete.com/articles/javascript-boulderdash/objects.pdf
; https://bitbucket.org/czirkoszoltan/gdash/src/c8390151fb1181a7d8c81df8eab67ab2cbf018e0/src/misc/helptext.cpp#lines-223

%import sounds

cave {
    ; for now we use the original cave dimension limits
    const uword MAX_CAVE_WIDTH = 40             ; word here to avoid having to cast to word all the time
    const ubyte MAX_CAVE_HEIGHT = 22
    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    const ubyte ROCKFORD_IDLE = 1
    const ubyte ROCKFORD_MOVING = 2
    const ubyte ROCKFORD_PUSHING = 3
    const ubyte ROCKFORD_BLINKING = 4
    const ubyte ROCKFORD_TAPPING = 5
    const ubyte ROCKFORD_TAPBLINK = 6
    const ubyte ROCKFORD_BIRTH = 7
    const ubyte ROCKFORD_FACE_LEFT = 1
    const ubyte ROCKFORD_FACE_RIGHT = 2

    const ubyte AMOEBA_SLOW_GROWTH = 8      ; 3.1%
    const ubyte AMOEBA_FAST_GROWTH = 64     ; 25%
    const ubyte AMOEBA_MAX_SIZE = 200

    const ubyte ACTION_NOTHING = 0
    const ubyte ACTION_RESTARTLEVEL = 1
    const ubyte ACTION_NEXTLEVEL = 2
    const ubyte ACTION_GAMEOVER = 3

    const ubyte CAVE_SPEED_NORMAL = 8           ; should be 7 officially, but that is too fast on 60hz refresh
    const ubyte CAVE_SPEED_INTERMISSION = 6     ; intermissions play at a higher movement speed

    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 0)
    uword cell_attributes = memory("attributes_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 0)
    ubyte width
    ubyte height
    bool intermission
    bool scroll_enabled
    str name = "?" * 40
    str description = "?" * 127

    ubyte cave_number       ; 1+
    ubyte difficulty        ; 1-5
    ubyte magicwall_millingtime_sec
    ubyte amoeba_slow_time_sec
    ubyte initial_diamond_value
    ubyte extra_diamond_value
    ubyte diamonds_needed
    ubyte cave_time_sec
    ubyte cave_speed
    ubyte color_background1
    ubyte color_background2
    ubyte color_foreground

    bool covered
    ubyte scan_frame
    ubyte player_x
    ubyte player_y
    byte rockford_birth_time        ; in frames, default = 120  (2 seconds)
    ubyte rockford_state            ; 0 = no player in the cave at all
    ubyte rockford_face_direction
    ubyte rockford_animation_frame
    uword bonusbg_timer
    bool bonusbg_enabled
    uword magicwall_timer
    bool magicwall_enabled
    bool magicwall_expired
    ubyte slime_permeability
    ubyte amoeba_count
    bool amoeba_enclosed
    ubyte amoeba_explodes_to
    ubyte amoeba_growth_rate
    uword amoeba_slow_timer
    ubyte num_diamonds
    ubyte num_lives
    bool player_died
    ubyte player_died_timer
    uword score
    uword score_500_for_bonus
    ubyte time_left_secs
    ubyte current_diamond_value
    bool exit_reached

    ; The attribute of a cell.
    ; Can only have one of these active attributes at a time, except the FLAG ones.
    const ubyte ATTR_SCANNED_FLAG = 128     ; cell has already been scanned this frame
    const ubyte ATTR_COVERED_FLAG = 64      ; used to uncover a new level gradually
    const ubyte ATTR_FALLING      = 1       ; boulders/diamonds etc that are falling
    const ubyte ATTR_MOVING_LEFT  = 2       ; movements of a creature
    const ubyte ATTR_MOVING_RIGHT = 3
    const ubyte ATTR_MOVING_UP    = 4
    const ubyte ATTR_MOVING_DOWN  = 5


    sub init() {
        sys.memset(cells, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, objects.dirt)
    }

    sub restart_level() {
        cover_all()
        disable_bonusbg()
        disable_magicwall(true)
        magicwall_expired = false    ; first time is not expired
        amoeba_count = 0
        num_diamonds = 0
        amoeba_enclosed = false
        amoeba_growth_rate = AMOEBA_SLOW_GROWTH
        amoeba_slow_timer = (amoeba_slow_time_sec as uword) * 60
        exit_reached = false
        rockford_state = 0
        player_died = false
        scan_frame = 0
        current_diamond_value = initial_diamond_value
        time_left_secs = 0
        screen.white_flash = false
        scroll_enabled = true
        ; find the initial player position
        ubyte x
        ubyte y
        for y in 0 to height-1 {
            for x in 0 to width-1 {
                cx16.r0L = @(cells + y*MAX_CAVE_WIDTH + x)
                if cx16.r0L == objects.inboxclosed or cx16.r0L == objects.inboxblinking {
                    player_x = x
                    player_y = y
                    break
                }
            }
        }
    }

    sub set_tile(ubyte col, ubyte row, ubyte id, ubyte attr) {
        uword offset = row*MAX_CAVE_WIDTH + col
        @(cells + offset) = id
        @(cell_attributes + offset) = attr
    }

    uword @requirezp cell_ptr2      ; free to use
    uword @requirezp attr_ptr2      ; free to use

    ubyte jiffy_counter

    sub do_each_frame() {
        ; called by vsync irq handler to do timing critical stuff that should
        ; be independent of how many frames a full cave scan takes.
        if covered
            return

        handle_rockford_animation()

        jiffy_counter++
        if jiffy_counter==60 {
            jiffy_counter=0
            if time_left_secs {
                time_left_secs--
                if time_left_secs <= 10
                    sounds.timeout(time_left_secs)
            }
        }

        if amoeba_count and (jiffy_counter & 3 == 0)
            sounds.amoeba()
        if magicwall_enabled and (jiffy_counter & 3 == 1)
            sounds.magicwall()
    }


    sub scan() -> ubyte {
        if covered
            return ACTION_NOTHING  ; we do nothing else as long as the cave is still (partially) covered.

        rockford_birth_time--
        if exit_reached {
            magicwall_enabled = false
            amoeba_count = 0
            if intermission {
                num_lives++
                enable_bonusbg()
                intermission = false
            }
            if time_left_secs and interrupts.vsync_counter % 3 == 0 {
                add_score(cave.difficulty)
                sounds.bonus(time_left_secs)
                time_left_secs--
            }
            if time_left_secs==0
                return ACTION_NEXTLEVEL
            return ACTION_NOTHING
        }

        if bonusbg_enabled {
            bonusbg_timer--
            if bonusbg_timer==0
                disable_bonusbg()
        }
        if magicwall_enabled {
            magicwall_timer--
            if magicwall_timer==0
                disable_magicwall(false)
        }

        if cbm.GETIN()==27 {
            ; escape is pressed. Lose a life and restart the level
            if intermission==false
                num_lives--
            player_died = true
            player_died_timer = 4
        }

        if player_died {
            player_died_timer--
            if player_died_timer==0 {
                player_died = false
                if num_lives==0
                    return ACTION_GAMEOVER
                return ACTION_RESTARTLEVEL
            }
        }

        amoeba_slow_timer--
        if amoeba_slow_timer==0
            amoeba_growth_rate = AMOEBA_FAST_GROWTH

        scan_frame++
        if scan_frame==cave_speed            ; cave scan is done once every X frames
            scan_frame = 0
        else
            return ACTION_NOTHING

        ; amoeba handling
        if amoeba_count >= AMOEBA_MAX_SIZE {
            replace_object(objects.amoeba, objects.amoebaexplosion)
            restart_anim(objects.amoebaexplosion)
            amoeba_explodes_to = objects.boulder
            amoeba_enclosed = false
        } else if amoeba_enclosed {
            replace_object(objects.amoeba, objects.amoebaexplosion)
            restart_anim(objects.amoebaexplosion)
            amoeba_explodes_to = objects.diamond
            amoeba_enclosed = false
        } else {
            amoeba_enclosed = amoeba_count>0        ; will be scanned
        }
        amoeba_count = 0      ; will be scanned

        if screen.white_flash
            screen.flash_white(false)

        uword @requirezp cell_ptr       ; warning: never change this in a handler routine!! use cell_ptr2
        uword @requirezp attr_ptr       ; warning: never change this in a handler routine!! use attr_ptr2
        ubyte @zp x
        ubyte @zp y
        for y in 0 to height-1 {
            cell_ptr = cells + y*MAX_CAVE_WIDTH
            attr_ptr = cell_attributes + y*MAX_CAVE_WIDTH
            for x in 0 to width-1 {
                ubyte @zp attr = @(attr_ptr)
                if attr & ATTR_SCANNED_FLAG == 0 {
                    ubyte @zp obj = @(cell_ptr)
                    when obj {
                        objects.firefly, objects.altbutterfly -> {
                            handle_firefly()
                        }
                        objects.butterfly, objects.altfirefly, objects.stonefly -> {
                            handle_butterfly()
                        }
                        objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
                            if @(cell_ptr + MAX_CAVE_WIDTH) == objects.slime {
                                sink_through_slime()
                                ; make sure this object is not scanned again below when dealing with falling objects
                                @(attr_ptr) |= ATTR_SCANNED_FLAG
                                attr = @(attr_ptr)
                            }
                        }
                        objects.amoeba -> {
                            handle_amoeba()
                        }
                        ; NOTE: add other object scans in between here.
                        objects.outboxclosed -> {
                            if num_diamonds >= diamonds_needed {
                                sounds.crack()
                                screen.flash_white(true)
                                @(cell_ptr) = objects.outboxblinking
                                current_diamond_value = extra_diamond_value
                            }
                        }
                        objects.inboxclosed -> {
                            @(cell_ptr) = objects.inboxblinking
                            rockford_birth_time = 120
                        }
                        objects.inboxblinking -> {
                            if rockford_birth_time<=0 {
                                ; spawn our guy, start the timer
                                sounds.crack()
                                restart_anim(objects.rockfordbirth)
                                rockford_state = ROCKFORD_BIRTH
                                rockford_face_direction = ROCKFORD_FACE_LEFT
                                rockford_animation_frame = 0
                                player_x = x
                                player_y = y
                                ; note we need to remove the inbox immediately otherwise it keeps blinking
                                @(cells + player_y*MAX_CAVE_WIDTH+player_x) = objects.rockfordbirth
                                jiffy_counter = 1
                                time_left_secs = cave_time_sec
                            }
                        }
                        objects.explosion -> {
                            if anim_ended(objects.explosion)
                                @(cell_ptr) = objects.space
                        }
                        objects.diamondbirth -> {
                            if anim_ended(objects.diamondbirth)
                                @(cell_ptr) = objects.diamond
                        }
                        objects.steelbirth -> {
                            if anim_ended(objects.steelbirth)
                                @(cell_ptr) = objects.steel
                        }
                        objects.boulderbirth -> {
                            if anim_ended(objects.boulderbirth)
                                @(cell_ptr) = objects.boulder
                        }
                        objects.amoebaexplosion -> {
                            if anim_ended(objects.amoebaexplosion)
                                @(cell_ptr) = amoeba_explodes_to
                        }
                        objects.horizexpander -> handle_horiz_expander()
                        objects.vertexpander -> handle_vert_expander()
                        objects.bothexpander -> handle_both_expander()
                    }
                    if objects.attributes[obj] & objects.ATTRF_ROCKFORD {
                        if not exit_reached
                            handle_rockford()
                    }
                    if objects.attributes[obj] & objects.ATTRF_FALLABLE {
                        if attr & ATTR_SCANNED_FLAG == 0 {
                            if attr==ATTR_FALLING {
                                handle_falling_object()
                            } else {
                                if @(cell_ptr + MAX_CAVE_WIDTH) == objects.space {
                                    ; immediately start falling 1 cell down
                                    fall_down_one_cell()
                                    play_fall_sound(obj)
                                }
                                else if objects.attributes[@(cell_ptr + MAX_CAVE_WIDTH)] & objects.ATTRF_ROUNDED {
                                    ; stationary boulders and diamonds can roll off something as well, as long as that is stationary
                                    roll_off()
                                }
                            }
                        }
                    }

                    @(attr_ptr) |= ATTR_SCANNED_FLAG
                }
                cell_ptr++
                attr_ptr++
            }
        }

        clear_all_scanned()
        return ACTION_NOTHING

        ; various handler subroutines follow:

        sub handle_falling_object() {
            ubyte obj_below = @(cell_ptr + MAX_CAVE_WIDTH)
            ubyte attr_below = objects.attributes[obj_below]
            if obj_below==objects.space {
                ; cell below is empty, simply move down and continue falling
                fall_down_one_cell()
            } else if obj_below==objects.magicwallinactive {
                enable_magicwall()
                sink_through_magicwall()
            } else if obj_below==objects.magicwall {
                sink_through_magicwall()
            } else if obj_below==objects.slime {
                sink_through_slime()
            } else if attr_below & objects.ATTRF_ROUNDED {
                roll_off()
            } else if attr_below & objects.ATTRF_ROCKFORD {
                explode(x, y+1)
            } else if attr_below & objects.ATTRF_EXPLODABLE {
                explode(x, y+1)
            } else {
                ; stop falling; it is blocked by something
                @(attr_ptr) = 0
                play_fall_sound(@(cell_ptr))
            }
        }

        sub sink_through_magicwall() {
            ; this only happens when an objects is FALLING on the magic wall,
            ; if it is already resting on it, it stays in place and this routine isn't called. (unlike slime)
            play_fall_magicwall_sound(@(cell_ptr))
            if magicwall_expired {
                ; simply remove the object, nothing comes out
                @(cell_ptr) = objects.space
            } else {
                if @(cell_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH)==objects.space {
                    ; fall through the magic wall
                    ubyte new_object
                    when @(cell_ptr) {
                        objects.diamond -> new_object = objects.boulder
                        objects.diamond2 -> new_object = objects.megaboulder
                        objects.boulder -> new_object = objects.diamond
                        objects.megaboulder -> new_object = objects.diamond2
                        else -> return
                    }
                    @(cell_ptr) = objects.space
                    @(cell_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH) = new_object
                    @(attr_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                } else {
                    ; cannot fall through the wall (obstructed), remove object
                    @(cell_ptr) = objects.space
                }
            }
        }

        sub sink_through_slime() {
            ; both falling and stationary boulders and diamonds can sink through slime.
            if (bdcff.bdrandom() & slime_permeability) == 0 {
                if @(cell_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH)==objects.space {
                    @(cell_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH) = @(cell_ptr)
                    @(attr_ptr + MAX_CAVE_WIDTH + MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                    @(cell_ptr) = objects.space
                }
            }
        }

        sub handle_amoeba() {
            amoeba_count++
            ubyte obj_up = @(cell_ptr-MAX_CAVE_WIDTH)
            ubyte obj_left = @(cell_ptr-1)
            ubyte obj_right = @(cell_ptr+1)
            ubyte obj_down = @(cell_ptr+MAX_CAVE_WIDTH)
            ubyte direction = bdcff.bdrandom() & 3
            bool grow = bdcff.bdrandom() < cave.amoeba_growth_rate
            if obj_up == objects.space or obj_up == objects.dirt or obj_up == objects.dirt {
                amoeba_enclosed = false
                if grow and direction==0 {
                    @(cell_ptr-MAX_CAVE_WIDTH) = objects.amoeba
                }
            }
            if obj_down == objects.space or obj_down == objects.dirt or obj_down == objects.dirt2 {
                amoeba_enclosed = false
                if grow and direction==1 {
                    @(cell_ptr+MAX_CAVE_WIDTH) = objects.amoeba
                    @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                }
            }
            if obj_left == objects.space or obj_left == objects.dirt or obj_left == objects.dirt2 {
                amoeba_enclosed = false
                if grow and direction==2 {
                    @(cell_ptr-1) = objects.amoeba
                }
            }
            if obj_right == objects.space or obj_right == objects.dirt or obj_right == objects.dirt2 {
                amoeba_enclosed = false
                if grow and direction==3 {
                    @(cell_ptr+1) = objects.amoeba
                    @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                }
            }
        }

        sub handle_firefly() {
            ; Movement rules: if it touches Rockford or Amoeba it explodes
            ; tries to rotate 90 degrees left and move to empty cell in new or original direction
            ; if not possible rotate 90 right and wait for next update

            if touches_rockford_or_amoeba(x, y) {
                explode(x, y)
                return
            }
            ubyte new_dir = rotate_90_left(attr)
            uword target_cell_ptr = get_cell_ptr_for_direction(new_dir)
            uword target_attr_ptr = get_attr_ptr_for_direction(new_dir)
            if @(target_cell_ptr)==objects.space {
                @(cell_ptr) = objects.space
                @(attr_ptr) = 0
                @(target_cell_ptr) = obj
                @(target_attr_ptr) = new_dir | ATTR_SCANNED_FLAG
                return
            }
            target_cell_ptr = get_cell_ptr_for_direction(attr)
            target_attr_ptr = get_attr_ptr_for_direction(attr)
            if @(target_cell_ptr)==objects.space {
                @(cell_ptr) = objects.space
                @(attr_ptr) = 0
                @(target_cell_ptr) = obj
                @(target_attr_ptr) = attr | ATTR_SCANNED_FLAG
                return
            }
            @(attr_ptr) = rotate_90_right(attr)
        }

        sub handle_butterfly() {
            ; Movement rules: if it touches Rockford or Amoeba it explodes
            ; tries to rotate 90 degrees right and move to empty cell in new or original direction
            ; if not possible rotate 90 left and wait for next update
            if touches_rockford_or_amoeba(x, y) {
                explode(x, y)
                return
            }
            ubyte new_dir = rotate_90_right(attr)
            uword target_cell_ptr = get_cell_ptr_for_direction(new_dir)
            uword target_attr_ptr = get_attr_ptr_for_direction(new_dir)
            if @(target_cell_ptr)==objects.space {
                @(cell_ptr) = objects.space
                @(attr_ptr) = 0
                @(target_cell_ptr) = obj
                @(target_attr_ptr) = new_dir | ATTR_SCANNED_FLAG
                return
            }
            target_cell_ptr = get_cell_ptr_for_direction(attr)
            target_attr_ptr = get_attr_ptr_for_direction(attr)
            if @(target_cell_ptr)==objects.space {
                @(cell_ptr) = objects.space
                @(attr_ptr) = 0
                @(target_cell_ptr) = obj
                @(target_attr_ptr) = attr | ATTR_SCANNED_FLAG
                return
            }
            @(attr_ptr) = rotate_90_left(attr)
        }

        sub handle_rockford() {
            ; note: rockford animation is done independently (each frame).
            ubyte targetcell
            bool eatable
            ubyte afterboulder
            ubyte moved = false

            if time_left_secs==0 and rockford_state {
                ; explode (and lose a life in the process)
                explode(player_x, player_y)
                return
            }

            if main.game_state==main.STATE_DEMO {
                if cbm.GETIN()==27 {
                    ; escape was pressed, abort the demo
                    exit_reached=true
                    time_left_secs=0
                    while cbm.GETIN()==27 {
                        ; wait until key released
                    }
                    return
                }
                bd1demo.get_movement()
            }
            else {
                joystick.scan()
            }

            if joystick.left left()
            else if joystick.right right()
            else if joystick.up up()
            else if joystick.down down()
            else if rockford_state==ROCKFORD_MOVING or rockford_state==ROCKFORD_PUSHING
                rockford_state=ROCKFORD_IDLE

            uword offset = player_y*MAX_CAVE_WIDTH + player_x
            cell_ptr2 = cells + offset
            attr_ptr2 = cell_attributes + offset
            if moved {
                when @(cell_ptr2) {
                    objects.outboxhidden, objects.outboxblinking -> exit_reached = true
                    objects.diamond, objects.diamond2, objects.diamondbirth -> pickup_diamond()
                    objects.dirt, objects.dirt2 -> sounds.rockfordmove_dirt()
                    objects.space -> sounds.rockfordmove_space()
                }
                @(cell_ptr) = objects.space
                @(attr_ptr) = ATTR_SCANNED_FLAG
            }
            @(cell_ptr2) = active_rockford_object()
            @(attr_ptr2) = ATTR_SCANNED_FLAG

            sub left() {
                rockford_face_direction = ROCKFORD_FACE_LEFT
                targetcell = @(cell_ptr-1)
                eatable = rockford_can_eat(targetcell)
                if targetcell==objects.boulder or targetcell==objects.megaboulder {
                    rockford_state = ROCKFORD_PUSHING
                    if targetcell!=objects.megaboulder and @(attr_ptr-1) != ATTR_FALLING {
                        afterboulder = @(cell_ptr-2)
                        if afterboulder==objects.space {
                            ; 1/8 chance to push boulder left
                            if bdcff.bdrandom() < 32 {
                                sounds.boulder()
                                @(cell_ptr-2) = targetcell
                                @(cell_ptr-1) = objects.space
                                if not joystick.fire {
                                    player_x--
                                    moved = true
                                }
                            }
                        }
                    }
                } else if joystick.fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        when targetcell {
                            objects.diamond, objects.diamond2, objects.diamondbirth -> pickup_diamond()
                            objects.dirt, objects.dirt2 -> sounds.rockfordmove_dirt()
                        }
                        @(cell_ptr-1) = objects.space
                    }
                } else {
                    rockford_state = ROCKFORD_MOVING
                    if eatable {
                        player_x--
                        moved = true
                    }
                }
            }

            sub right() {
                rockford_face_direction = ROCKFORD_FACE_RIGHT
                targetcell = @(cell_ptr+1)
                eatable = rockford_can_eat(targetcell)
                if targetcell==objects.boulder or targetcell==objects.megaboulder {
                    rockford_state = ROCKFORD_PUSHING
                    if targetcell!=objects.megaboulder and @(attr_ptr+1) != ATTR_FALLING {
                        afterboulder = @(cell_ptr+2)
                        if afterboulder==objects.space {
                            ; 1/8 chance to push boulder right
                            if bdcff.bdrandom() < 32 {
                                sounds.boulder()
                                @(cell_ptr+2) = targetcell
                                @(attr_ptr+2) |= ATTR_SCANNED_FLAG
                                if @(cell_ptr+2+MAX_CAVE_WIDTH) == objects.space
                                    @(attr_ptr+2) |= ATTR_FALLING   ; to avoid being able to roll something over a hole
                                @(cell_ptr+1) = objects.space
                                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                                if not joystick.fire {
                                    player_x++
                                    moved = true
                                }
                            }
                        }
                    }
                } else if joystick.fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        when targetcell {
                            objects.diamond, objects.diamond2, objects.diamondbirth -> pickup_diamond()
                            objects.dirt, objects.dirt2 -> sounds.rockfordmove_dirt()
                        }
                        @(cell_ptr+1) = objects.space
                        @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                    }
                } else {
                    rockford_state = ROCKFORD_MOVING
                    if eatable {
                        player_x++
                        moved = true
                    }
                }
            }

            sub up() {
                targetcell = @(cell_ptr-MAX_CAVE_WIDTH)
                eatable = rockford_can_eat(targetcell)
                if targetcell==objects.boulder or targetcell==objects.megaboulder {
                    ; cannot push or snip boulder up so do nothing.
                    rockford_state = ROCKFORD_MOVING
                } else if joystick.fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        when targetcell {
                            objects.diamond, objects.diamond2, objects.diamondbirth -> pickup_diamond()
                            objects.dirt, objects.dirt2 -> sounds.rockfordmove_dirt()
                        }
                        @(cell_ptr-MAX_CAVE_WIDTH) = objects.space
                    }
                } else {
                    rockford_state = ROCKFORD_MOVING
                    if eatable {
                        player_y--
                        moved = true
                    }
                }
            }

            sub down() {
                targetcell = @(cell_ptr+MAX_CAVE_WIDTH)
                eatable = rockford_can_eat(targetcell)
                if targetcell==objects.boulder or targetcell==objects.megaboulder {
                    ; cannot push or snip boulder down so do nothing.
                    rockford_state = ROCKFORD_MOVING
                } else if joystick.fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        when targetcell {
                            objects.diamond, objects.diamond2, objects.diamondbirth -> pickup_diamond()
                            objects.dirt, objects.dirt2 -> sounds.rockfordmove_dirt()
                        }
                        @(cell_ptr+MAX_CAVE_WIDTH) = objects.space
                        @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                    }
                } else {
                    rockford_state = ROCKFORD_MOVING
                    if eatable {
                        player_y++
                        moved = true
                    }
                }
            }

            sub rockford_can_eat(ubyte object) -> bool {
                return objects.attributes[object] & objects.ATTRF_EATABLE
            }

            sub active_rockford_object() -> ubyte {
                when rockford_state {
                    ROCKFORD_MOVING -> {
                        if rockford_face_direction == ROCKFORD_FACE_LEFT
                            return objects.rockfordleft
                        return objects.rockfordright
                    }
                    ROCKFORD_PUSHING -> {
                        if rockford_face_direction == ROCKFORD_FACE_LEFT
                            return objects.rockfordpushleft
                        return objects.rockfordpushright
                    }
                    ROCKFORD_BIRTH -> {
                        if anim_ended(objects.rockfordbirth) {
                            rockford_state = ROCKFORD_IDLE
                            rockford_animation_frame = 0
                        }
                        return objects.rockfordbirth
                    }
                    ROCKFORD_TAPPING -> return objects.rockfordtap
                    ROCKFORD_BLINKING -> return objects.rockfordblink
                    ROCKFORD_TAPBLINK -> return objects.rockfordtapblink
                    else -> return objects.rockford
                }
            }
        }

        sub handle_horiz_expander() {
            bool playsound = false
            if @(cell_ptr-1)==objects.space {
                @(cell_ptr-1) = objects.horizexpander
                playsound = true
            }
            if @(cell_ptr+1)==objects.space {
                @(cell_ptr+1) = objects.horizexpander
                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                playsound = true
            }
            if playsound
                sounds.expanding_wall()
        }

        sub handle_vert_expander() {
            bool playsound = false
            if @(cell_ptr-MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr-MAX_CAVE_WIDTH) = objects.vertexpander
                playsound = true
            }
            if @(cell_ptr+MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr+MAX_CAVE_WIDTH) = objects.vertexpander
                @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                playsound = true
            }
            if playsound
                sounds.expanding_wall()
        }

        sub handle_both_expander() {
            bool playsound = false
            if @(cell_ptr-1)==objects.space {
                @(cell_ptr-1) = objects.bothexpander
                playsound = true
            }
            if @(cell_ptr+1)==objects.space {
                @(cell_ptr+1) = objects.bothexpander
                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                playsound = true
            }
            if @(cell_ptr-MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr-MAX_CAVE_WIDTH) = objects.bothexpander
                playsound = true
            }
            if @(cell_ptr+MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr+MAX_CAVE_WIDTH) = objects.bothexpander
                @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                playsound = true
            }
            if playsound
                sounds.expanding_wall()
        }

        sub fall_down_one_cell() {
            @(cell_ptr) = objects.space
            @(attr_ptr) = 0
            @(cell_ptr + MAX_CAVE_WIDTH) = obj
            @(attr_ptr + MAX_CAVE_WIDTH) = ATTR_FALLING | ATTR_SCANNED_FLAG
        }

        sub roll_off() {
            if @(attr_ptr + MAX_CAVE_WIDTH) != ATTR_FALLING {
                ; roll off a stationary round object under us, to the left or right, if there's room
                if @(cell_ptr-1) == objects.space and @(cell_ptr-1+MAX_CAVE_WIDTH) == objects.space {
                    ; roll left
                    if @(attr_ptr) != ATTR_FALLING
                        play_fall_sound(@(cell_ptr))
                    @(cell_ptr) = objects.space
                    @(cell_ptr-1) = obj
                    @(attr_ptr-1) = attr | ATTR_FALLING | ATTR_SCANNED_FLAG
                } else if @(cell_ptr+1) == objects.space and @(cell_ptr+1+MAX_CAVE_WIDTH) == objects.space {
                    ; roll right
                    if @(attr_ptr) != ATTR_FALLING
                        play_fall_sound(@(cell_ptr))
                    @(cell_ptr) = objects.space
                    @(cell_ptr+1) = obj
                    @(attr_ptr+1) = attr | ATTR_FALLING | ATTR_SCANNED_FLAG
                } else if @(attr_ptr) == ATTR_FALLING {
                    ; it stopped falling
                    play_fall_sound(@(cell_ptr))
                }
                @(attr_ptr) = 0   ; previous position: no falling anymore.
            }
        }

        sub get_cell_ptr_for_direction(ubyte dir) -> uword{
            when dir {
                ATTR_MOVING_UP -> return cell_ptr - MAX_CAVE_WIDTH
                ATTR_MOVING_DOWN -> return cell_ptr + MAX_CAVE_WIDTH
                ATTR_MOVING_LEFT -> return cell_ptr - 1
                ATTR_MOVING_RIGHT -> return cell_ptr + 1
                else -> return cell_ptr
            }
        }

        sub get_attr_ptr_for_direction(ubyte dir) -> uword{
            when dir {
                ATTR_MOVING_UP -> return attr_ptr - MAX_CAVE_WIDTH
                ATTR_MOVING_DOWN -> return attr_ptr + MAX_CAVE_WIDTH
                ATTR_MOVING_LEFT -> return attr_ptr - 1
                ATTR_MOVING_RIGHT -> return attr_ptr + 1
                else -> return attr_ptr
            }
        }

        sub rotate_90_left(ubyte dir) -> ubyte {
            when dir {
                ATTR_MOVING_UP -> return ATTR_MOVING_LEFT
                ATTR_MOVING_LEFT -> return ATTR_MOVING_DOWN
                ATTR_MOVING_DOWN -> return ATTR_MOVING_RIGHT
                ATTR_MOVING_RIGHT -> return ATTR_MOVING_UP
                else -> return dir
            }
        }

        sub rotate_90_right(ubyte dir) -> ubyte {
            when dir {
                ATTR_MOVING_UP -> return ATTR_MOVING_RIGHT
                ATTR_MOVING_LEFT -> return ATTR_MOVING_UP
                ATTR_MOVING_DOWN -> return ATTR_MOVING_LEFT
                ATTR_MOVING_RIGHT -> return ATTR_MOVING_DOWN
                else -> return dir
            }
        }

        sub explode(ubyte xx, ubyte yy) {
            ubyte what = @(cells + yy*MAX_CAVE_WIDTH + xx)
            ubyte how
            when what {
                objects.butterfly, objects.altbutterfly -> how = objects.diamondbirth
                objects.stonefly -> how = objects.boulderbirth
                else -> how = objects.explosion
            }
            restart_anim(how)
            sounds.explosion()
            cell_ptr2 = cells + (yy-1)*MAX_CAVE_WIDTH + xx-1
            attr_ptr2 = cell_attributes + (yy-1)*MAX_CAVE_WIDTH + xx-1
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()
            cell_ptr2 += MAX_CAVE_WIDTH - 2
            attr_ptr2 += MAX_CAVE_WIDTH - 2
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()
            cell_ptr2 += MAX_CAVE_WIDTH - 2
            attr_ptr2 += MAX_CAVE_WIDTH - 2
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()
            cell_ptr2++
            attr_ptr2++
            explode_cell()

            sub explode_cell() {
                if objects.attributes[@(cell_ptr2)] & objects.ATTRF_ROCKFORD {
                    rockford_state = 0
                    @(cell_ptr2) = how
                    @(attr_ptr2) |= ATTR_SCANNED_FLAG
                    if intermission==false
                        num_lives--
                    player_died = true
                    player_died_timer = 150
                }
                if objects.attributes[@(cell_ptr2)] & objects.ATTRF_CONSUMABLE {
                    @(cell_ptr2) = how
                    @(attr_ptr2) |= ATTR_SCANNED_FLAG
                }
            }
        }

        sub touches_rockford_or_amoeba(ubyte xx, ubyte yy) -> bool {
            uword @requirezp touch_ptr = cells + yy*MAX_CAVE_WIDTH + xx
            ubyte obj_up = @(touch_ptr-MAX_CAVE_WIDTH)
            ubyte obj_left = @(touch_ptr-1)
            ubyte obj_right = @(touch_ptr+1)
            ubyte obj_down = @(touch_ptr+MAX_CAVE_WIDTH)
            return obj_up==objects.amoeba or objects.attributes[obj_up] & objects.ATTRF_ROCKFORD
                or obj_down==objects.amoeba or objects.attributes[obj_down] & objects.ATTRF_ROCKFORD
                or obj_left==objects.amoeba or objects.attributes[obj_left] & objects.ATTRF_ROCKFORD
                or obj_right==objects.amoeba or objects.attributes[obj_right] & objects.ATTRF_ROCKFORD
        }
    }

    sub pickup_diamond() {
        num_diamonds++
        add_score(current_diamond_value)
        sounds.diamond_pickup()
    }

    sub add_score(ubyte amount) {
        score += amount
        score_500_for_bonus += amount
        if score_500_for_bonus >= 500 {
            score_500_for_bonus -= 500
            num_lives++
            enable_bonusbg()
        }
    }

    sub play_fall_sound(ubyte object) {
        if object==objects.diamond or object==objects.diamond2
            sounds.diamond()
        else if object==objects.boulder or object==objects.megaboulder
            sounds.boulder()
    }

    sub play_fall_magicwall_sound(ubyte object) {
        if object==objects.diamond or object==objects.diamond2
            sounds.boulder()
        else if object==objects.boulder or object==objects.megaboulder
            sounds.diamond()
    }
    
    sub handle_rockford_animation() {
        ; per frame, not per cave scan
        if not rockford_state
            return

        rockford_animation_frame++
        if rockford_animation_frame==8*2  {
            ; shortcut: we know that each rockford animation sequence is 8 steps times 2 frames each.
            rockford_animation_frame = 0
            if rockford_state!=ROCKFORD_MOVING and rockford_state!=ROCKFORD_PUSHING
                choose_new_anim()
        }

        sub choose_new_anim() {
            ubyte random = bdcff.bdrandom()
            bool set_blinking = false
            bool set_tapping = rockford_state==ROCKFORD_TAPBLINK or rockford_state==ROCKFORD_TAPPING
            if random < 64 {
                ; 25% chance to blink
                set_blinking = true
            }
            if random < 16 {
                ; 6.25% chance to start or stop tapping
                set_tapping = not set_tapping
            }
            if set_blinking {
                if set_tapping {
                    rockford_state = ROCKFORD_TAPBLINK
                    restart_anim(objects.rockfordtapblink)
                } else {
                    rockford_state = ROCKFORD_BLINKING
                    restart_anim(objects.rockfordblink)
                }
            } else {
                if set_tapping {
                    rockford_state = ROCKFORD_TAPPING
                    restart_anim(objects.rockfordtap)
                } else {
                    rockford_state = ROCKFORD_IDLE
                }
            }
        }
    }

    sub anim_ended(ubyte object) -> bool {
        return objects.anim_cycles[object]>0
    }

    sub restart_anim(ubyte object) {
        objects.anim_frame[object] = 0
        objects.anim_delay[object] = 0
        objects.anim_cycles[object] = 0
    }

    sub clear_all_scanned() {
        uword @zp ptr = cell_attributes
        repeat MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT {
            @(ptr) &= ~ATTR_SCANNED_FLAG
            ptr++
        }
    }

    ubyte uncover_cnt
    sub uncover_more() {
        if not covered
            return
        attr_ptr2 = cell_attributes
        repeat cave.MAX_CAVE_HEIGHT {
            if bdcff.bdrandom() & 1 {
                ubyte x = bdcff.bdrandom() % (cave.MAX_CAVE_WIDTH-1)
                @(attr_ptr2 + x) &= ~ATTR_COVERED_FLAG
            }
            attr_ptr2 += MAX_CAVE_WIDTH
        }
        uncover_cnt++
        if uncover_cnt>160
            uncover_all()

        if uncover_cnt & 3 == 0
            sounds.uncover()
    }

    sub cover_all() {
        uword @zp ptr = cell_attributes
        repeat MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT {
            @(ptr) |= ATTR_COVERED_FLAG
            ptr++
        }
        covered = true
        uncover_cnt = 0
    }

    sub uncover_all() {
        uword @zp ptr = cell_attributes
        repeat MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT {
            @(ptr) &= ~ATTR_COVERED_FLAG
            ptr++
        }
        covered = false
        uncover_cnt = 0
    }

    sub enable_bonusbg() {
        bonusbg_tile_lo = objects.tile_lo[objects.space]
        bonusbg_tile_hi = objects.tile_hi[objects.space]
        bonusbg_palette_offset = objects.palette_offsets_preshifted[objects.space]
        bonusbg_animsize = objects.anim_sizes[objects.space]
        bonusbg_animspeed = objects.anim_speeds[objects.space]
        objects.tile_lo[objects.space] = objects.tile_lo[objects.bonusbg]
        objects.tile_hi[objects.space] = objects.tile_hi[objects.bonusbg]
        objects.palette_offsets_preshifted[objects.space] = objects.palette_offsets_preshifted[objects.bonusbg]
        objects.anim_sizes[objects.space] = objects.anim_sizes[objects.bonusbg]
        objects.anim_speeds[objects.space] = objects.anim_speeds[objects.bonusbg]
        objects.attributes[objects.space] |= objects.ATTRF_LOOPINGANIM
        bonusbg_enabled = true
        bonusbg_timer = 5*60
    }

    sub disable_bonusbg() {
        if not bonusbg_enabled
            return
        objects.tile_lo[objects.space] = bonusbg_tile_lo
        objects.tile_hi[objects.space] = bonusbg_tile_hi
        objects.palette_offsets_preshifted[objects.space] = bonusbg_palette_offset
        objects.anim_sizes[objects.space] = bonusbg_animsize
        objects.anim_speeds[objects.space] = bonusbg_animspeed
        objects.anim_frame[objects.space] = 0
        bonusbg_enabled = false
    }
    ubyte bonusbg_tile_lo
    ubyte bonusbg_tile_hi
    ubyte bonusbg_palette_offset
    ubyte bonusbg_animsize
    ubyte bonusbg_animspeed

    sub enable_magicwall() {
        if magicwall_expired
            return
        magicwall_enabled = true
        magicwall_timer = (cave.magicwall_millingtime_sec as uword) * 60
        replace_object(objects.magicwallinactive, objects.magicwall)
    }

    sub disable_magicwall(bool force) {
        if force or magicwall_enabled {
            magicwall_enabled = false
            magicwall_expired = true
            replace_object(objects.magicwall, objects.magicwallinactive)
        }
    }

    sub replace_object(ubyte original, ubyte new) {
        cell_ptr2 = cells
        attr_ptr2 = cell_attributes
        repeat MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT {
            if @(cell_ptr2)==original {
                @(cell_ptr2) = new
                @(attr_ptr2) |= ATTR_SCANNED_FLAG
            }
            cell_ptr2++
            attr_ptr2++
        }
    }
}

joystick {
    ubyte active_joystick   ; 0-4 where 0 = the 'keyboard' joystick
    bool up
    bool down
    bool left
    bool right
    bool start
    bool fire

    sub scan() {
        cx16.r1 = cx16.joystick_get2(active_joystick)
        left = lsb(cx16.r1) & %0010==0
        right = lsb(cx16.r1) & %0001==0
        up = lsb(cx16.r1) & %1000==0
        down = lsb(cx16.r1) & %0100==0
        fire = cx16.r1 & %1100000011000000 != %1100000011000000
        start = cx16.r1 & %0000000000010000 == 0
    }

    sub clear() {
        fire = false
        start = false
        left = false
        right = false
        up = false
        down = false
    }
}
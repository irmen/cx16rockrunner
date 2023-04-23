%import math

; documentation about object behaviors:
; https://codeincomplete.com/articles/javascript-boulderdash/objects.pdf
; https://bitbucket.org/czirkoszoltan/gdash/src/c8390151fb1181a7d8c81df8eab67ab2cbf018e0/src/misc/helptext.cpp#lines-223

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

    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword cell_attributes = memory("attributes_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    ubyte width = MAX_CAVE_WIDTH
    ubyte height = MAX_CAVE_HEIGHT
    uword name_ptr
    uword description_ptr
    bool intermission

    ubyte cave_number
    ubyte magicwall_millingtime_sec
    ubyte amoeba_slow_time_sec
    ubyte initial_diamond_value
    ubyte extra_diamond_value
    ubyte diamonds_needed
    ubyte cave_time_sec
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
    ubyte amoeba_count
    bool amoeba_enclosed
    ubyte amoeba_explodes_to
    ubyte amoeba_growth_rate
    uword amoeba_slow_timer
    ubyte num_diamonds
    ubyte num_lives
    uword score
    uword score_500_for_bonus
    uword cave_time_left            ; frames
    ubyte current_diamond_value
    bool exit_reached
    bool playing_demo
    bool joy_fire
    bool joy_up
    bool joy_down
    bool joy_left
    bool joy_right

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
        cover_all()
    }

    sub restart_level() {
        cover_all()
        bonusbg_enabled = false
        magicwall_enabled = false
        magicwall_expired = false
        playing_demo = false
        amoeba_count = 0
        num_diamonds = 0
        amoeba_enclosed = false
        amoeba_growth_rate = AMOEBA_SLOW_GROWTH
        amoeba_slow_timer = (amoeba_slow_time_sec as uword) * 60
        exit_reached = false
        rockford_state = 0
        scan_frame = 0
        current_diamond_value = initial_diamond_value
        cave_time_left = (cave_time_sec as uword) * 60
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

    sub scan() {
        if covered {
            uncover_more()
            return      ; we do nothing else as long as the cave is still (partially) covered.
        }

        rockford_birth_time--
        handle_rockford_animation()

        if bonusbg_enabled {
            bonusbg_timer--
            if bonusbg_timer==0
                disable_bonusbg()
        }
        if magicwall_enabled {
            magicwall_timer--
            if magicwall_timer==0
                disable_magicwall()
        }

        if exit_reached {
            ; TODO do cave exit stuff: add remaining time to score + next level
            return
        }

        cave_time_left--
        if cave_time_left==0 {
            if rockford_state {
                ; explode (and lose a life in the process)
                explode(player_x, player_y)
            }
        }
        amoeba_slow_timer--
        if amoeba_slow_timer==0
            amoeba_growth_rate = AMOEBA_FAST_GROWTH

        scan_frame++
        if scan_frame==7            ; cave scan is done once every 7 frames TODO configurable
            scan_frame = 0
        else
            return

        if score_500_for_bonus >= 500 {
            score_500_for_bonus -= 500
            num_lives++
            enable_bonusbg()
        }

        ; does amoeba explode?
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
                        objects.amoeba -> {
                            handle_amoeba()
                        }
                        ; TODO add other object scans here
                        objects.outboxclosed -> {
                            if num_diamonds >= diamonds_needed {
                                ; TODO flash screen to indicate outbox is now open
                                sounds.crack()
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
                                ; spawn our guy
                                sounds.crack()
                                restart_anim(objects.rockfordbirth)
                                rockford_state = ROCKFORD_BIRTH
                                rockford_face_direction = ROCKFORD_FACE_LEFT
                                rockford_animation_frame = 0
                                player_x = x
                                player_y = y
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
                        objects.horizexpander -> {
                            handle_horiz_expander()
                        }
                        objects.vertexpander -> {
                            handle_vert_expander()
                        }
                    }
                    if objects.attributes[obj] & objects.ATTRF_ROCKFORD {
                        if not exit_reached
                            handle_rockford()
                    }
                    if objects.attributes[obj] & objects.ATTRF_FALLABLE {
                        if attr==ATTR_FALLING {
                            handle_falling_object()
                        } else {
                            when @(cell_ptr + MAX_CAVE_WIDTH) {
                                objects.space -> {
                                    ; immediately start falling 1 cell down
                                    fall_down_one_cell()
                                    play_fall_sound(obj)
                                }
                                objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
                                    ; stationary boulders and diamonds can roll off something as well
                                    roll_off()
                                }
                            }
                        }
                    }
                }
                cell_ptr++
                attr_ptr++
            }
        }

        clear_all_scanned()

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

            sub sink_through_magicwall() {
                ; this only happens when an objects is FALLING on the magic wall,
                ; if it is already resting on it, it stays in place and this routine isn't called
                play_fall_magicwall_sound(@(cell_ptr))
                if magicwall_expired {
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
                        ; cannot fall through the wall, so stop falling
                        @(attr_ptr) = ATTR_SCANNED_FLAG
                    }
                }
            }

            sub sink_through_slime() {
                if math.rnd() > 32      ; TODO configurable permeability
                    return
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
            ubyte direction = math.rnd() & 3
            bool grow = math.rnd() < cave.amoeba_growth_rate
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

            if playing_demo
                bd1demo.get_movement()
            else {
                uword joy = cx16.joystick_get2(main.joystick)
                joy_left = lsb(joy) & %0010==0
                joy_right = lsb(joy) & %0001==0
                joy_up = lsb(joy) & %1000==0
                joy_down = lsb(joy) & %0100==0
                joy_fire = joy & %1100000001100000 != %1100000001100000
            }

            if joy_left left()
            else if joy_right right()
            else if joy_up up()
            else if joy_down down()
            else if rockford_state==ROCKFORD_MOVING or rockford_state==ROCKFORD_PUSHING
                rockford_state=ROCKFORD_IDLE

            if moved {
                @(cell_ptr) = objects.space
                cell_ptr2 = cells + player_y*MAX_CAVE_WIDTH + player_x
                attr_ptr2 = cell_attributes + player_y*MAX_CAVE_WIDTH + player_x
                targetcell = @(cell_ptr2)
                @(cell_ptr2) = objects.rockford      ; exact tile will be set by rockford animation routine
                @(attr_ptr2) = ATTR_SCANNED_FLAG
                if targetcell==objects.outboxhidden or targetcell==objects.outboxblinking {
                    exit_reached = true
                }
                if targetcell==objects.diamond or targetcell==objects.diamond2 {
                    num_diamonds++
                    score += current_diamond_value
                    score_500_for_bonus += current_diamond_value
                    sounds.diamond_pickup()
                }
                if targetcell==objects.dirt or targetcell==objects.dirt2 {
                    sounds.rockfordmove_dirt()
                }
                if targetcell==objects.space or targetcell==objects.bonusbg {
                    sounds.rockfordmove_space()
                }
            }

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
                            if math.rnd() < 32 {
                                sounds.boulder()
                                @(cell_ptr-2) = targetcell
                                @(cell_ptr-1) = objects.space
                                if not joy_fire {
                                    player_x--
                                    moved = true
                                }
                            }
                        }
                    }
                } else if joy_fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        if targetcell==objects.diamond or targetcell==objects.diamond2
                            sounds.diamond_pickup()
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
                            if math.rnd() < 32 {
                                sounds.boulder()
                                @(cell_ptr+2) = targetcell
                                @(attr_ptr+2) |= ATTR_SCANNED_FLAG | ATTR_FALLING           ; falling to avoid rolling over a hole
                                @(cell_ptr+1) = objects.space
                                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                                if not joy_fire {
                                    player_x++
                                    moved = true
                                }
                            }
                        }
                    }
                } else if joy_fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        if targetcell==objects.diamond or targetcell==objects.diamond2
                            sounds.diamond_pickup()
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
                } else if joy_fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        if targetcell==objects.diamond or targetcell==objects.diamond2
                            sounds.diamond_pickup()
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
                } else if joy_fire {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable and targetcell!=objects.outboxhidden and targetcell!=objects.outboxblinking {
                        if targetcell==objects.diamond or targetcell==objects.diamond2
                            sounds.diamond_pickup()
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

            cell_ptr2 = cells + player_y*MAX_CAVE_WIDTH + player_x

            when rockford_state {
                ROCKFORD_MOVING -> {
                    if rockford_face_direction == ROCKFORD_FACE_LEFT
                        @(cell_ptr2) = objects.rockfordleft
                    else
                        @(cell_ptr2) = objects.rockfordright
                }
                ROCKFORD_PUSHING -> {
                    if rockford_face_direction == ROCKFORD_FACE_LEFT
                        @(cell_ptr2) = objects.rockfordpushleft
                    else
                        @(cell_ptr2) = objects.rockfordpushright
                }
                ROCKFORD_BIRTH -> {
                    @(cell_ptr2) = objects.rockfordbirth
                    if anim_ended(objects.rockfordbirth) {
                        rockford_state = ROCKFORD_IDLE
                        rockford_animation_frame = 0
                    }
                }
                ROCKFORD_TAPPING -> @(cell_ptr2) = objects.rockfordtap
                ROCKFORD_BLINKING -> @(cell_ptr2) = objects.rockfordblink
                ROCKFORD_TAPBLINK -> @(cell_ptr2) = objects.rockfordtapblink
                ROCKFORD_IDLE -> @(cell_ptr2) = objects.rockford
            }

            sub choose_new_anim() {
                ubyte random = math.rnd()
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

        sub handle_horiz_expander() {
            if @(cell_ptr-1)==objects.space {
                @(cell_ptr-1) = objects.horizexpander
                sounds.expanding_wall()
            }
            if @(cell_ptr+1)==objects.space {
                @(cell_ptr+1) = objects.horizexpander
                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                sounds.expanding_wall()
            }
        }

        sub handle_vert_expander() {
            if @(cell_ptr-MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr-MAX_CAVE_WIDTH) = objects.vertexpander
                sounds.expanding_wall()
            }
            if @(cell_ptr+MAX_CAVE_WIDTH)==objects.space {
                @(cell_ptr+MAX_CAVE_WIDTH) = objects.vertexpander
                @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
                sounds.expanding_wall()
            }
        }

        sub anim_ended(ubyte object) -> bool {
            return objects.anim_cycles[object]>0
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
                    @(attr_ptr-1) = attr | ATTR_FALLING
                } else if @(cell_ptr+1) == objects.space and @(cell_ptr+1+MAX_CAVE_WIDTH) == objects.space {
                    ; roll right
                    if @(attr_ptr) != ATTR_FALLING
                        play_fall_sound(@(cell_ptr))
                    @(cell_ptr) = objects.space
                    @(cell_ptr+1) = obj
                    @(attr_ptr+1) = attr | ATTR_FALLING
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
                    num_lives--
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
            if math.rnd() & 1 {
                ubyte x = math.rnd() % (cave.MAX_CAVE_WIDTH-1)
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

    sub disable_magicwall() {
        magicwall_enabled = false
        magicwall_expired = true
        replace_object(objects.magicwall, objects.magicwallinactive)
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

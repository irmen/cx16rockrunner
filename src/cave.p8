%import math

; documentation about object behaviors:
; https://codeincomplete.com/articles/javascript-boulderdash/objects.pdf

cave {
    ; for now we use the original cave dimension limits
    const ubyte MAX_CAVE_WIDTH = 40
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

    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword cell_attributes = memory("attributes_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword name_ptr
    uword description_ptr
    ubyte width = MAX_CAVE_WIDTH
    ubyte height = MAX_CAVE_HEIGHT
    bool intermission
    bool covered
    ubyte scan_frame
    ubyte player_x
    ubyte player_y
    byte rockford_birth_time        ; in frames, default = 120  (2 seconds)
    ubyte rockford_state            ; 0 = no player in the cave at all
    ubyte rockford_face_direction
    ubyte rockford_animation_frame
    ubyte bonusbg_timer
    bool bonusbg_enabled

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
        bonusbg_enabled = false
    }

    sub set_tile(ubyte col, ubyte row, ubyte id, ubyte attr) {
        uword offset = (row as uword)*MAX_CAVE_WIDTH + col
        @(cells + offset) = id
        @(cell_attributes + offset) = attr
    }

    sub scan() {
        if covered
            return      ; we do nothing as long as the cave is still (partially) covered.

        rockford_birth_time--
        handle_rockford_animation()

        scan_frame++
        if scan_frame==7            ; cave scan is done once every 7 frames TODO configurable
            scan_frame = 0
        else
            return

        if bonusbg_enabled {
            bonusbg_timer--
            if_z
                disable_bonusbg()
        }

        uword @requirezp cell_ptr
        uword @requirezp attr_ptr
        ubyte @zp x
        ubyte @zp y
        for y in 0 to height-1 {
            cell_ptr = cells + (y as uword) * MAX_CAVE_WIDTH
            attr_ptr = cell_attributes + (y as uword) * MAX_CAVE_WIDTH
            for x in 0 to width-1 {
                ubyte @zp attr = @(attr_ptr)
                if attr & ATTR_SCANNED_FLAG == 0 {
                    ubyte @zp obj = @(cell_ptr)
                    when obj {
                        objects.firefly, objects.altfirefly, objects.bladder -> {
                            handle_firefly()
                        }
                        objects.butterfly, objects.altbutterfly, objects.stonefly -> {
                            handle_butterfly()
                        }
                        objects.inboxclosed -> {
                            @(cell_ptr) = objects.inboxblinking
                            rockford_birth_time = 120
                        }
                        objects.inboxblinking -> {
                            if rockford_birth_time<=0 {
                                ; spawn our guy
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
                        objects.amoeba -> {
                            ; TODO amoeba handling
                        }
                        objects.amoebaexplosion -> {
                            if anim_ended(objects.amoebaexplosion) {
                                @(cell_ptr) = objects.boulder   ;  TODO sometimes diamonds instead!
                            }
                        }
                        objects.biter -> {
                            ; TODO biter behavior
                        }
                        objects.horizexpander -> {
                            ; TODO horiz expand
                        }
                        objects.vertexpander -> {
                            ; TODO vertical expand
                        }
                        objects.magicwall -> {
                            ; TODO disable magic wall after certain time
                        }
                    }
                    if objects.attributes[obj] & objects.ATTRF_ROCKFORD {
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

        ; TODO amoeba growth etc...
        clear_all_scanned()

        sub handle_falling_object() {
            ubyte obj_below = @(cell_ptr + MAX_CAVE_WIDTH)
            ubyte attr_below = objects.attributes[obj_below]
            if obj_below==objects.space {
                ; cell below is empty, simply move down and continue falling
                fall_down_one_cell()
            } else if attr_below & objects.ATTRF_ROUNDED {
                roll_off()
            } else if attr_below & objects.ATTRF_ROCKFORD {
                explode(x, y+1)
            } else if attr_below & objects.ATTRF_EXPLODE_SPACES or attr_below & objects.ATTRF_EXPLODE_DIAMONDS {
                explode(x, y+1)
            } else {
                ; stop falling; it is blocked by something
                @(attr_ptr) = 0
            }
            ; TODO check if falling boulder hits a magic wall
            ; TODO check if falling boulder hits permeable slime
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
            uword joy = cx16.joystick_get2(main.joystick)
            bool firebutton = joy & %1100000001100000 != %1100000001100000
            ubyte targetcell
            bool eatable
            ubyte afterboulder
            ubyte moved = false

            ; TODO if cave time runs out, explode and lose a life.
            ; TODO if x diamonds or points collected, add life + enable_bonusbg()

            if lsb(joy) & %0010 == 0 left()
            else if lsb(joy) & %0001 == 0 right()
            else if lsb(joy) & %1000 == 0 up()
            else if lsb(joy) & %0100 == 0 down()
            else if rockford_state==ROCKFORD_MOVING or rockford_state==ROCKFORD_PUSHING
                rockford_state=ROCKFORD_IDLE

            if moved {
                @(cell_ptr) = objects.space
                cell_ptr = cells + (player_y as uword) * MAX_CAVE_WIDTH + player_x
                attr_ptr = cell_attributes + (player_y as uword) * MAX_CAVE_WIDTH + player_x
                @(cell_ptr) = objects.rockford      ; exact tile will be set by rockford animation routine
                @(attr_ptr) = ATTR_SCANNED_FLAG
            }

            sub left() {
                rockford_face_direction = ROCKFORD_FACE_LEFT
                targetcell = @(cell_ptr-1)
                eatable = rockford_can_eat(targetcell)
                if targetcell==objects.boulder or targetcell==objects.megaboulder {
                    rockford_state = ROCKFORD_PUSHING
                    if @(attr_ptr-1) != ATTR_FALLING {
                        afterboulder = @(cell_ptr-2)
                        if afterboulder==objects.space {
                            ; 1/8 chance to push boulder left
                            if math.rnd() < 32 {
                                @(cell_ptr-2) = targetcell
                                @(cell_ptr-1) = objects.space
                                if not firebutton {
                                    player_x--
                                    moved = true
                                }
                            }
                        }
                    }
                } else if firebutton {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable
                        @(cell_ptr-1) = objects.space
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
                    if @(attr_ptr+1) != ATTR_FALLING {
                        afterboulder = @(cell_ptr+2)
                        if afterboulder==objects.space {
                            ; 1/8 chance to push boulder right
                            if math.rnd() < 32 {
                                @(cell_ptr+2) = targetcell
                                @(attr_ptr+2) |= ATTR_SCANNED_FLAG | ATTR_FALLING           ; falling to avoid rolling over a hole
                                @(cell_ptr+1) = objects.space
                                @(attr_ptr+1) |= ATTR_SCANNED_FLAG
                                if not firebutton {
                                    player_x++
                                    moved = true
                                }
                            }
                        }
                    }
                } else if firebutton {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable
                        @(cell_ptr+1) = objects.space
                        @(attr_ptr+1) |= ATTR_SCANNED_FLAG
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
                } else if firebutton {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable
                        @(cell_ptr-MAX_CAVE_WIDTH) = objects.space
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
                } else if firebutton {
                    rockford_state = ROCKFORD_PUSHING
                    if eatable
                        @(cell_ptr+MAX_CAVE_WIDTH) = objects.space
                        @(attr_ptr+MAX_CAVE_WIDTH) |= ATTR_SCANNED_FLAG
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

            cell_ptr = cells + (player_y as uword) * MAX_CAVE_WIDTH + player_x

            when rockford_state {
                ROCKFORD_MOVING -> {
                    if rockford_face_direction == ROCKFORD_FACE_LEFT
                        @(cell_ptr) = objects.rockfordleft
                    else
                        @(cell_ptr) = objects.rockfordright
                }
                ROCKFORD_PUSHING -> {
                    if rockford_face_direction == ROCKFORD_FACE_LEFT
                        @(cell_ptr) = objects.rockfordpushleft
                    else
                        @(cell_ptr) = objects.rockfordpushright
                }
                ROCKFORD_BIRTH -> {
                    @(cell_ptr) = objects.rockfordbirth
                    if anim_ended(objects.rockfordbirth) {
                        rockford_state = ROCKFORD_IDLE
                        rockford_animation_frame = 0
                    }
                }
                ROCKFORD_TAPPING -> @(cell_ptr) = objects.rockfordtap
                ROCKFORD_BLINKING -> @(cell_ptr) = objects.rockfordblink
                ROCKFORD_TAPBLINK -> @(cell_ptr) = objects.rockfordtapblink
                ROCKFORD_IDLE -> @(cell_ptr) = objects.rockford
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
                    @(cell_ptr) = objects.space
                    @(cell_ptr-1) = obj
                    @(attr_ptr-1) = attr | ATTR_FALLING
                } else if @(cell_ptr+1) == objects.space and @(cell_ptr+1+MAX_CAVE_WIDTH) == objects.space {
                    ; roll right
                    @(cell_ptr) = objects.space
                    @(cell_ptr+1) = obj
                    @(attr_ptr+1) = attr | ATTR_FALLING
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
            ubyte what = @(cells + (yy as uword) * MAX_CAVE_WIDTH + xx)
            ubyte how = objects.attributes[what]
            if how & objects.ATTRF_EXPLODE_DIAMONDS
                how = objects.diamondbirth
            else if how & objects.ATTRF_EXPLODE_SPACES
                how = objects.explosion
            else
                sys.exit(1)
            restart_anim(how)
            uword @requirezp cell_ptr2 = cells + ((yy-1) as uword) * MAX_CAVE_WIDTH + xx-1
            uword @requirezp attr_ptr2 = cell_attributes + ((yy-1) as uword) * MAX_CAVE_WIDTH + xx-1
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
                    ; TODO lose a life
                }
                if objects.attributes[@(cell_ptr2)] & objects.ATTRF_CONSUMABLE {
                    @(cell_ptr2) = how
                    @(attr_ptr2) |= ATTR_SCANNED_FLAG
                }
            }
        }

        sub touches_rockford_or_amoeba(ubyte xx, ubyte yy) -> bool {
            uword @requirezp touch_ptr = cells + (yy as uword) * MAX_CAVE_WIDTH + xx
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
    }

    sub enable_bonusbg() {
        ubyte tile_lo = objects.tile_lo[objects.space]
        ubyte tile_hi = objects.tile_hi[objects.space]
        ubyte palette_offset = objects.palette_offsets_preshifted[objects.space]
        ubyte animsize = objects.anim_sizes[objects.space]
        ubyte animspeed = objects.anim_speeds[objects.space]
        objects.tile_lo[objects.space] = objects.tile_lo[objects.bonusbg]
        objects.tile_hi[objects.space] = objects.tile_hi[objects.bonusbg]
        objects.palette_offsets_preshifted[objects.space] = objects.palette_offsets_preshifted[objects.bonusbg]
        objects.anim_sizes[objects.space] = objects.anim_sizes[objects.bonusbg]
        objects.anim_speeds[objects.space] = objects.anim_speeds[objects.bonusbg]
        objects.attributes[objects.space] |= objects.ATTRF_LOOPINGANIM
        bonusbg_enabled = true
        bonusbg_timer = 35
    }

    sub disable_bonusbg() {
        objects.tile_lo[objects.space] = cave.enable_bonusbg.tile_lo
        objects.tile_hi[objects.space] = cave.enable_bonusbg.tile_hi
        objects.palette_offsets_preshifted[objects.space] = cave.enable_bonusbg.palette_offset
        objects.anim_sizes[objects.space] = cave.enable_bonusbg.animsize
        objects.anim_speeds[objects.space] = cave.enable_bonusbg.animspeed
        objects.anim_frame[objects.space] = 0
        bonusbg_enabled = false
    }

    ubyte uncover_cnt
    sub uncover_more() {
        if not covered
            return
        repeat 10 {
            ubyte x = math.rnd() % width
            ubyte y = math.rnd() % height
            @(cell_attributes + (y as uword)*MAX_CAVE_WIDTH + x) &= ~ATTR_COVERED_FLAG
        }
        uncover_cnt++
        if uncover_cnt>180
            uncover_all()
    }
}

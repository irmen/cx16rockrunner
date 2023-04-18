
; documentation about object behaviors:
; https://codeincomplete.com/articles/javascript-boulderdash/objects.pdf

cave {
    ; for now we use the original cave dimension limits
    const ubyte MAX_CAVE_WIDTH = 40
    const ubyte MAX_CAVE_HEIGHT = 22
    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword cell_attributes = memory("attributes_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    uword name_ptr
    uword description_ptr
    ubyte width = MAX_CAVE_WIDTH
    ubyte height = MAX_CAVE_HEIGHT
    bool intermission
    bool covered
    ubyte scan_frame

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

    sub set_tile(ubyte col, ubyte row, ubyte id, ubyte attr) {
        uword offset = (row as uword)*MAX_CAVE_WIDTH + col
        @(cells + offset) = id
        @(cell_attributes + offset) = attr
    }


;    sub get_tile(ubyte col, ubyte row, ubyte id) -> ubyte {
;        return @(cells + (row as uword)*MAX_CAVE_WIDTH + col)
;    }
;
;    sub get_attr(ubyte col, ubyte row) -> ubyte {
;        return @(cell_attributes + (row as uword)*MAX_CAVE_WIDTH + col)
;    }

    sub scan() {
        if covered
            return
        scan_frame++
        if scan_frame==7            ; cave scan is done once every 7 frames
            scan_frame = 0
        else
            return

        ; TODO finish cavescan
        ubyte @zp y
        for y in 0 to height {
            uword cell_ptr = cells + (y as uword) * MAX_CAVE_WIDTH
            uword attr_ptr = cell_attributes + (y as uword) * MAX_CAVE_WIDTH
            repeat width {
                ubyte @requirezp attr = @(attr_ptr)
                if attr & ATTR_SCANNED_FLAG == 0 {
                    ubyte @requirezp obj = @(cell_ptr)
                    when obj {
                        objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
                            if attr==ATTR_FALLING {
                                handle_falling_object()
                            } else {
                                if @(cell_ptr + MAX_CAVE_WIDTH)==objects.space {
                                    ; immediately start falling 1 cell down
                                    fall_down_one_cell()
                                }
                                ; TODO stationary boulders and diamonds can roll off to the left/right as well
                            }
                        }
                        objects.firefly, objects.altfirefly -> {
                            handle_firefly()
                        }
                        objects.butterfly, objects.altbutterfly, objects.stonefly -> {
                            handle_butterfly()
                        }
                        ; TODO handle other objects
                    }
                }
                cell_ptr++
                attr_ptr++
            }
        }

        ; TODO amoeba growth
        clear_all_scanned()


        sub fall_down_one_cell() {
            @(cell_ptr) = objects.space
            @(attr_ptr) = 0
            @(cell_ptr + MAX_CAVE_WIDTH) = obj
            @(attr_ptr + MAX_CAVE_WIDTH) = ATTR_FALLING | ATTR_SCANNED_FLAG
        }

        sub handle_falling_object() {
            when @(cell_ptr + MAX_CAVE_WIDTH) {
                objects.space -> {
                    ; cell below is empty, simply move down and continue falling
                    fall_down_one_cell()
                }
                objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
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
                objects.rockfordleft, objects.rockfordright,
                objects.rockfordpushleft, objects.rockfordpushright,
                objects.rockfordblink, objects.rockfordtap,
                objects.rockfordtapblink, objects.rockfordbirth -> {
                    ; TODO explode Rockford
                }
                ; TODO check if another explosive object is below the boulder (firefly, butterfly, ...?)
                ; TODO check if falling boulder hits a magic wall
                ; TODO check if falling boulder hits slime
                else -> {
                    ; stop falling; it is blocked by something
                    @(attr_ptr) = 0
                }
            }
        }

        sub handle_firefly() {
            ; Movement rules: if it touches Rockford or Amoeba it explodes  TODO implement explosion
            ; tries to rotate 90 degrees left and move to empty cell in new or original direction
            ; if not possible rotate 90 right and wait for next update
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
            ; Movement rules: if it touches Rockford or Amoeba it explodes TODO implement explosion
            ; tries to rotate 90 degrees right and move to empty cell in new or original direction
            ; if not possible rotate 90 left and wait for next update
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

    ubyte uncover_cnt
    sub uncover_more() {
        if not covered
            return
        repeat 8 {
            ubyte x = math.rnd() % width
            ubyte y = math.rnd() % height
            @(cell_attributes + (y as uword)*MAX_CAVE_WIDTH + x) &= ~ATTR_COVERED_FLAG
        }
        uncover_cnt++
        if uncover_cnt>180          ; TODO what is the correct time uncovering should take?
            uncover_all()
    }
}

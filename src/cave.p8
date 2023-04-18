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
    ; Can only have one of these active attributes at a time, except the scanned bit (bit 7).
    const ubyte ATTR_SCANNED_FLAG = 128     ; cell has already been scanned this frame
    const ubyte ATTR_COVERED      = 1       ; used to uncover a new level gradually
    const ubyte ATTR_FALLING      = 2       ; boulders/diamonds etc that are falling
    const ubyte ATTR_MOVING_LEFT  = 3       ; movements of a creature
    const ubyte ATTR_MOVING_RIGHT = 4
    const ubyte ATTR_MOVING_UP    = 5
    const ubyte ATTR_MOVING_DOWN  = 6


    sub init() {
        sys.memset(cells, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, objects.dirt)
        cover_all()
    }

    sub set_tile(ubyte col, ubyte row, ubyte id, ubyte attr) {
        uword offset = (row as uword)*MAX_CAVE_WIDTH + col
        @(cells + offset) = id
        @(cell_attributes + offset) = attr
    }

    sub set_attr(ubyte col, ubyte row, ubyte attr) {
        @(cell_attributes + (row as uword)*MAX_CAVE_WIDTH + col) = attr
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

        ; TODO cavescan
        ubyte @zp y
        for y in 0 to height {
            uword cell_ptr = cells + (y as uword) * MAX_CAVE_WIDTH
            uword attr_ptr = cell_attributes + (y as uword) * MAX_CAVE_WIDTH
            repeat width {
                ubyte @requirezp obj = @(cell_ptr)
                ubyte @requirezp attr = @(attr_ptr)
                if attr & ATTR_SCANNED_FLAG == 0 {
                    when obj {
                        objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
                            if attr==ATTR_FALLING {
                                handle_falling_object()
                            } else {
                                if @(cell_ptr + MAX_CAVE_WIDTH)==objects.space {
                                    @(attr_ptr) = ATTR_FALLING | ATTR_SCANNED_FLAG      ; start falling   TODO immediately fall 1 position or not?
                                }
                            }
                        }
                        objects.firefly, objects.altfirefly -> {
                            ; TODO move firefly, depending on current direction in attr
                        }
                        objects.butterfly, objects.altbutterfly, objects.stonefly -> {
                            ; TODO move butterfly, depending on current direction in attr
                        }
                        ; TODO handle other objects
                    }
                    @(attr_ptr) |= ATTR_SCANNED_FLAG        ; TODO not needed here?
                }
                cell_ptr++
                attr_ptr++
            }
        }

        sub handle_falling_object() {
            when @(cell_ptr + MAX_CAVE_WIDTH) {
                objects.space -> {
                    ; cell below is empty, simply move down and continue falling
                    @(cell_ptr) = objects.space
                    @(attr_ptr) = 0
                    @(cell_ptr + MAX_CAVE_WIDTH) = obj
                    @(attr_ptr + MAX_CAVE_WIDTH) = ATTR_FALLING | ATTR_SCANNED_FLAG
                }
                objects.boulder, objects.megaboulder, objects.diamond, objects.diamond2 -> {
                    if (@(attr_ptr + MAX_CAVE_WIDTH) & $7f) != ATTR_FALLING {
                        ; bounce off a stationary round object under us, to the left or right, if there's room
                        if @(cell_ptr-1) == objects.space and @(cell_ptr-1+MAX_CAVE_WIDTH) == objects.space {
                            ; bounce left
                            @(cell_ptr) = objects.space
                            @(attr_ptr) = 0
                            @(cell_ptr-1) = obj
                            @(attr_ptr-1) = attr
                        } else if @(cell_ptr+1) == objects.space and @(cell_ptr+1+MAX_CAVE_WIDTH) == objects.space {
                            ; bounce right
                            @(cell_ptr) = objects.space
                            @(attr_ptr) = 0
                            @(cell_ptr+1) = obj
                            @(attr_ptr+1) = attr
                        }
                        else {
                            ; stop falling; it is blocked by something
                            @(attr_ptr) = 0
                        }
                    }
                }
                objects.rockfordleft, objects.rockfordright,
                objects.rockfordpushleft, objects.rockfordpushright,
                objects.rockfordblink, objects.rockfordtap,
                objects.rockfordtapblink, objects.rockfordbirth -> {
                    ; TODO crush Rockford
                }
                else -> {
                    ; stop falling; it is blocked by something
                    @(attr_ptr) = 0
                }
            }
        }

        clear_all_scanned()
    }

    sub clear_all_scanned() {
        uword @zp ptr = cell_attributes
        repeat MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT {
            @(ptr) &= ~ATTR_SCANNED_FLAG
            ptr++
        }
    }

    sub cover_all() {
        sys.memset(cell_attributes, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, ATTR_COVERED)
        covered = true
        uncover_cnt = 0
    }

    sub uncover_all() {
        sys.memset(cell_attributes, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 0)
        covered = false
    }

    ubyte uncover_cnt
    sub uncover_more() {
        if not covered
            return
        uword num_cells = width*height
        repeat 8 {
            ubyte x = math.rnd() % width
            ubyte y = math.rnd() % height
            set_attr(x, y, 0)
        }
        uncover_cnt++
        if uncover_cnt>180          ; TODO what is the correct time uncovering should take?
            uncover_all()
    }
}

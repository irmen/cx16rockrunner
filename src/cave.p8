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

    sub set_tile(ubyte col, ubyte row, ubyte id) {
        @(cave.cells + (row as uword)*MAX_CAVE_WIDTH + col) = id
    }

    sub get_tile(ubyte col, ubyte row, ubyte id) -> ubyte {
        return @(cave.cells + (row as uword)*MAX_CAVE_WIDTH + col)
    }

    sub set_attr(ubyte col, ubyte row, ubyte attr) {
        @(cave.cell_attributes + (row as uword)*MAX_CAVE_WIDTH + col) = attr
    }

    sub get_attr(ubyte col, ubyte row) -> ubyte {
        return @(cave.cell_attributes + (row as uword)*MAX_CAVE_WIDTH + col)
    }

    sub scan() {
        scan_frame++
        if scan_frame==7            ; cave scan is done once every 7 frames
            scan_frame = 0
        else
            return

        ; TODO cavescan

        clear_all_scanned()
    }

    sub clear_all_scanned() {
        uword @zp ptr = cave.cell_attributes
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
        uword num_cells = cave.width*cave.height
        repeat 8 {
            ubyte x = math.rnd() % cave.width
            ubyte y = math.rnd() % cave.height
            cave.set_attr(x, y, 0)
        }
        uncover_cnt++
        if uncover_cnt>180          ; TODO what is the correct time uncovering should take?
            cave.uncover_all()
    }
}

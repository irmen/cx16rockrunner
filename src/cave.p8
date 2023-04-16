cave {
    ; for now we use the original cave dimension limits
    const ubyte MAX_CAVE_WIDTH = 40
    const ubyte MAX_CAVE_HEIGHT = 22
    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    uword name_ptr
    uword description_ptr
    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    ubyte width
    ubyte height
    bool intermission

    sub init() {
        sys.memset(cells, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, objects.space)
    }

    sub set_tile(ubyte col, ubyte row, ubyte id) {
        @(cave.cells + (row as uword)*MAX_CAVE_WIDTH + col) = id
    }

    sub fill_demotiles() {
        ubyte xx
        ubyte yy
        ubyte @zp obj_id = 0
        for yy in 0 to cave.VISIBLE_CELLS_V-1 {
            for xx in 0 to cave.VISIBLE_CELLS_H-1 {
                cave.cells[(yy as uword)*cave.MAX_CAVE_WIDTH + xx] = obj_id
                obj_id++
                if obj_id >= objects.NUM_OBJECTS
                    obj_id=0
            }
        }
    }


}

cave {
    ; for now we use the original cave dimension limits
    const ubyte MAX_CAVE_WIDTH = 40
    const ubyte MAX_CAVE_HEIGHT = 22
    const ubyte VISIBLE_CELLS_H = 320/16
    const ubyte VISIBLE_CELLS_V = 240/16

    uword name_ptr
    uword description_ptr
    uword cells = memory("objects_matrix", MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, 256)
    ubyte width = MAX_CAVE_WIDTH
    ubyte height = MAX_CAVE_HEIGHT
    bool intermission
    ubyte scan_frame

    sub init() {
        sys.memset(cells, MAX_CAVE_WIDTH*MAX_CAVE_HEIGHT, objects.covered)
    }

    sub set_tile(ubyte col, ubyte row, ubyte id) {
        @(cave.cells + (row as uword)*MAX_CAVE_WIDTH + col) = id
    }

    sub scan() {
        scan_frame++
        if scan_frame==7            ; cave scan is done once every 7 frames
            scan_frame = 0
        else
            return

        ; TODO cavescan
    }
}

%import diskio
%import textio
%import bdcff
%import string
%zeropage basicsafe

main {
    ubyte game_state
    ubyte joystick
    const ubyte STATE_CAVETITLE = 1
    const ubyte STATE_CHOOSE_LEVEL = 2
    const ubyte STATE_UNCOVERING = 3
    const ubyte STATE_PLAYING = 4
    const ubyte STATE_GAMEOVER = 5
    const ubyte STATE_DEMO = 6
    const ubyte STATE_SHOWING_HISCORE = 7
    const ubyte STATE_ENTER_NAME = 8

    sub start() {
        txt.lowercase()

        if bdcff.load_caveset("caves/boulderdash01.bd") {
            if bdcff.parse_caveset() {
                txt.print("\nCaveset Name: ")
                txt.print(bdcff.caveset_name)
                txt.print("\nCaveset Author: ")
                txt.print(bdcff.caveset_author)
                txt.nl()
                txt.print_ub(bdcff.num_caves)
                txt.print(" caves.\n")
                txt.print_ub(bdcff.num_levels)
                txt.print(" difficulty levels.\n\n")

                bdcff.parse_cave(1 )
                txt.print("cave name: ")
                txt.print(cave.name_ptr)
                txt.print("\ncave description: ")
                txt.print(cave.description_ptr)
                txt.nl()
            }
        }
    }

}

screen {
    bool white_flash
    sub flash_white(bool white) {
        white_flash = white
    }
}

bd1demo {
    sub get_movement() {
    }
}

interrupts {
    ubyte vsync_counter

}
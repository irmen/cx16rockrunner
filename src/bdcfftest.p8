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

        if bdcff.load_caveset("caves/boulderdash02.bd") {
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

                bdcff.parse_cave(5)

                txt.print("\n\nPARSED:\n")
                txt.print("cave name: ")
                txt.print(cave.name)
                txt.print("\ncave description: ")
                txt.print(cave.description)
                txt.print("\nsize: ")
                txt.print_ub(cave.width)
                txt.chrout('*')
                txt.print_ub(cave.height)
                txt.print("\nintermission: ")
                txt.print_ub(cave.intermission)
                txt.print("\ncavetimes: ")
                for cx16.r2L in 0 to bdcff.num_levels-1 {
                    txt.print_ub(bdcff.cave_times[cx16.r2L])
                    txt.spc()
                }
                txt.print("\nmagicwall time: ")
                txt.print_ub(cave.magicwall_millingtime_sec)
                txt.print("\namoeba time: ")
                txt.print_ub(cave.amoeba_slow_time_sec)
                txt.print("\nslime perm: ")
                txt.print_ub(cave.slime_permeability)
                txt.print("\ndiamond values: ")
                txt.print_ub(cave.initial_diamond_value)
                txt.spc()
                txt.print_ub(cave.extra_diamond_value)
                txt.print("\ndiamonds needed: ")
                for cx16.r2L in 0 to bdcff.num_levels-1 {
                    txt.print_ub(bdcff.required_diamonds[cx16.r2L])
                    txt.spc()
                }
                txt.print("\nrandseeds: ")
                for cx16.r2L in 0 to bdcff.num_levels-1 {
                    txt.print_ub(bdcff.rand_seeds[cx16.r2L])
                    txt.spc()
                }
                txt.print("\nrandomfill: ")
                if bdcff.randomfill_prob1 {
                    txt.print_ub(bdcff.randomfill_obj1)
                    txt.spc()
                    txt.print_ub(bdcff.randomfill_prob1)
                    txt.spc()
                }
                if bdcff.randomfill_prob2 {
                    txt.print_ub(bdcff.randomfill_obj2)
                    txt.spc()
                    txt.print_ub(bdcff.randomfill_prob2)
                    txt.spc()
                }
                if bdcff.randomfill_prob3 {
                    txt.print_ub(bdcff.randomfill_obj3)
                    txt.spc()
                    txt.print_ub(bdcff.randomfill_prob3)
                    txt.spc()
                }
                if bdcff.randomfill_prob4 {
                    txt.print_ub(bdcff.randomfill_obj4)
                    txt.spc()
                    txt.print_ub(bdcff.randomfill_prob4)
                    txt.spc()
                }
                txt.print("\ninitial fill: ")
                txt.print_ub(bdcff.initial_fill)
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
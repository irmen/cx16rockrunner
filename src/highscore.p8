%import diskio
%import string

highscore {
    ; data format:
    ; 64 bytes:  8 names of 7 letters + 0 byte each  for position 1 to 8
    ; 16 bytes:  8 words, the scores, for position 1 to 8
    ; total 80 bytes.

    sub get_score(ubyte pos) -> uword {
        return peekw(table+64+pos*2)
    }

    sub get_name(ubyte pos) -> uword {
        return table + pos*8
    }

    sub highscore_pos(uword score) -> ubyte {
        for cx16.r9L in 0 to 7 {
            if score > get_score(cx16.r9L)
                return cx16.r9L+1
        }
        return 0
    }

    sub record_score(str caveset_name, uword score, str name) {
        ubyte pos = highscore_pos(score)
        if pos!=0 {
            pos--
            cx16.r10 = table + 6*8
            cx16.r11 = table + 64 + 6*2
            for cx16.r9L in 6 downto pos {
                void string.copy(cx16.r10, cx16.r10+8)
                pokew(cx16.r11+2, peekw(cx16.r11))
                cx16.r10 -= 8
                cx16.r11 -= 2
            }
            pokew(cx16.r11+2, score)
            void string.copy(name, cx16.r10+8)
            save(caveset_name)
        }
    }

    str name_input = " "*8
    ubyte input_idx

    sub start_enter_name() {
        sys.memset(name_input, len(name_input), ' ')
        name_input[0] = $8a ; return key
        input_idx = 0
        while cbm.GETIN()!=0 { /* clear keyboard buffer */ }
    }

    sub enter_name() -> bool {
        ubyte letter = cbm.GETIN()
        when letter {
            13 -> {
                if input_idx!=0 {
                    name_input[input_idx] = 0
                    return true
                }
            }
            20, 25 -> {
                input_idx--
                if_neg
                    input_idx=0
                name_input[input_idx] = $8a
                name_input[input_idx+1] = ' '
            }
            0 -> {
                ; no keypress
            }
            else -> {
                if input_idx<7 {
                    name_input[input_idx] = letter
                    input_idx++
                    name_input[input_idx] = $8a
                }
            }
        }
        return false
    }

    sub save(str caveset_name) {
        diskio.chdir("hiscores")
        diskio.delete(caveset_name)
        void diskio.save_raw(caveset_name, table, 80)
        diskio.chdir("..")
    }


    uword table = memory("highscores", 80, 0)

    sub load(str caveset_name) {
        diskio.chdir("hiscores")
        if diskio.load_raw(caveset_name, table)!=0 and cbm.READST()&63==0  {     ; the READST is to work around an emulator bug on hostfs
            diskio.chdir("..")
            return
        }

        diskio.chdir("..")
        cx16.r9 = table
        repeat 8 {
            void string.copy("DesertF", cx16.r9)
            cx16.r9 += 8
        }
        cx16.r10 = 1600
        repeat 8 {
            pokew(cx16.r9, cx16.r10)
            cx16.r10 -= 200
            cx16.r9 += 2
        }

        save(caveset_name)
    }
}

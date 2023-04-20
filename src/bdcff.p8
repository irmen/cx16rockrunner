; Boulderdash Common File Format

bdcff {

    sub load_test_cave() {

        cave.player_x = 0
        cave.player_y = 0
        cave.name_ptr = "test cave"
        cave.description_ptr = "test cave description"
        cave.width = 40        ; hardcoded for these caves, also intermissions
        cave.height = 22       ; hardcoded for these caves, also intermissions
        cave.intermission = false
        cave.rockford_state = 0

        uword @zp ptr = &cave_data
        ubyte x
        ubyte y
        for y in 0 to cave.height-1 {
            for x in 0 to cave.width-1 {
                ubyte object = translate_object(@(ptr))
                cave.set_tile(x, y, object, translate_attr(@(ptr)))
                if object == objects.inboxclosed {
                    cave.player_x = x
                    cave.player_y = y
                }
                ptr++
            }
        }
    }

    sub translate_object(ubyte char) -> ubyte {
        when char {
            '.' -> return objects.dirt
            ' ' -> return objects.space
            'w' -> return objects.wall
            'M' -> return objects.magicwallinactive
            'x' -> return objects.horizexpander
            'v' -> return objects.vertexpander
            'H' -> return objects.outboxhidden
            'X' -> return objects.outboxclosed
            'W' -> return objects.steel
            'Q' -> return objects.firefly
            'q' -> return objects.firefly
            'O' -> return objects.firefly
            'o' -> return objects.firefly
            'c' -> return objects.butterfly
            'C' -> return objects.butterfly
            'b' -> return objects.butterfly
            'B' -> return objects.butterfly
            'r' -> return objects.boulder
            'd' -> return objects.diamond
            'P' -> return objects.inboxclosed
            'a' -> return objects.amoeba
            'F' -> return objects.voodoo
            's' -> return objects.slime
            '%' -> return objects.megaboulder
            ;; '*' -> return objects.lightboulder
            ;; 'e' -> return objects.expandingwall
            else -> return objects.space
        }
    }

    sub translate_attr(ubyte char) -> ubyte {
        when char {
            'Q' -> return cave.ATTR_MOVING_LEFT
            'q' -> return cave.ATTR_MOVING_RIGHT
            'O' -> return cave.ATTR_MOVING_UP
            'o' -> return cave.ATTR_MOVING_DOWN
            'c' -> return cave.ATTR_MOVING_DOWN
            'C' -> return cave.ATTR_MOVING_LEFT
            'b' -> return cave.ATTR_MOVING_UP
            'B' -> return cave.ATTR_MOVING_RIGHT
            else -> return 0
        }
    }

    cave_data:
    %asm {{
.text "                                        "
.text "                                        "
.text "           r                            "
.text "          dd                            "
.text "         r r                            "
.text "        d  d                            "
.text "       r   r                            "
.text "      d    d                            "
.text "     r   P r                            "
.text "........................................"
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.text "                                        "
.byte 0
    }}
        cave_data_2:
    %asm {{
.text " ssw..............................wss   "
.text " ssw.WWWWWWWWWWWWWWWWWWWWWWWWWWWW..wss  "
.text "ssw..W              W           W..wsss "
.text "ssw..W WWWWWWWWWWWW W WWWWWWWWW W.wssss "
.text "sssw.W W          W W W       W W..wssss"
.text "ssw..W W WWWWWWWW W W W WWWWW W W..wssss"
.text "ssw..W W       dW W W W    dW W W.wsssss"
.text "sssw.W WWWWWWWWWW W W WWWWWWWQW W..wssss"
.text "ssw..W            W W         W W..wssss"
.text "ssw..WWWWWWWWWWWWWW WWWWWWWWWWW W..wssss"
.text "sssw..W            P            W...wsss"
.text "sssw..W WWWWWWWWWWW WWWWWWWWWWWWWWW.wsss"
.text "sssw..W W         W Wc            W..wss"
.text "ssssw.W W WWWWWWW W W WWWWWWWWWWW W.wsss"
.text "sssw..W W W     W W W Wd        W W.wsss"
.text "sssw..W W W WXW W W W WWWWWWWWW W W..wss"
.text "ssssw.W W W  dW W W W           W W.wsss"
.text "sssw..W W WWWWW W W WWWWWWWWWWWWW W.wsss"
.text "sssw..W W       W W               W..wss"
.text "ssssw.W WWWWWWWWW WWWWWWWWWWWWWWWWW.wsss"
.text " ssw..W           W.................wss "
.text " ssw..WWWWWWWWWWWWW...wwwwwwwwwwwwwwss  "
.byte 0
    }}
}
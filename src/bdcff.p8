; Boulderdash Common File Format

%import conv
%import cave
%import objects

bdcff {

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
            'D' -> return objects.diamond2
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

    const ubyte FILE_BANK = 2
    ubyte cs_file_bank
    uword @zp cs_file_ptr

    const ubyte MAX_CAVES = 20
    ubyte num_caves
    ubyte num_levels
    str caveset_name = " " * 40
    str caveset_author = " " * 40

    ; pointers into the BDCFF caveset file:
    ubyte gameparams_bank
    uword gameparams_address
    ubyte[MAX_CAVES] cavespec_banks
    uword[MAX_CAVES] cavespec_addresses

    sub load_caveset(str filename) -> bool {
        txt.print("Loading caveset ")
        txt.print(filename)
        txt.nl()
        cs_file_bank = 0
        cs_file_ptr = 0
        cx16.rambank(FILE_BANK)
        cx16.r0 = diskio.load_raw(filename, $a000)
        if cx16.r0!=0 {
            @(cx16.r0) = 0
            cs_file_bank = FILE_BANK
            cs_file_ptr = $a000
            cx16.rambank(FILE_BANK)
            return true
        }
        return false
    }

    sub next_file_line_petscii() -> uword {
        const ubyte MAX_LINEBUF_SIZE = 128
        uword buffer = memory("bdcff_linebuf", MAX_LINEBUF_SIZE, 0)
        cx16.rambank(cs_file_bank)
        cx16.r2 = buffer
        cx16.r3L = 0    ; the length of the line we got so far
        while @(cs_file_ptr)!=0 {
            if eol() {
                while eol() inc_ptr()
                break
            }
            @(cx16.r2) = @(cs_file_ptr)
            cx16.r2++
            cx16.r3L++
            if cx16.r3L>=MAX_LINEBUF_SIZE-1 {
                ; avoid buffer overflow
                cx16.r2--
                cx16.r3L--
            }
            inc_ptr()
        }
        @(cx16.r2) = 0
        if buffer[0]==0
            return 0        ; EOF
        ascii_to_petscii(buffer)
        return buffer

        sub eol() -> bool {
            return @(cs_file_ptr)==iso:'\r' or @(cs_file_ptr)==iso:'\n'
        }

        sub inc_ptr() {
            cs_file_ptr++
            if cs_file_ptr == $c000 {
                ; hop to next hiram bank
                cs_file_ptr = $a000
                cs_file_bank++
                cx16.rambank(cs_file_bank)
            }
        }
    }

    sub parse_caveset() -> bool {
        if cs_file_ptr==0
            return false

        num_caves = 0
        num_levels = 0
        uword line

        repeat {
            line = next_file_line_petscii()
            if line==0
                break
            cx16.r0L = line[0]
            when line[0] {
                ';', 0 -> {
                    ; skip this line
                }
                '[' -> {
                    if line[1]=='/' and string.compare(line, "[/game]")==0
                        break
                    else if string.compare(line, "[game]")==0 {
                        gameparams_bank = cs_file_bank
                        gameparams_address = cs_file_ptr
                    }
                    else if string.compare(line, "[cave]")==0 {
                        cavespec_banks[num_caves] = cs_file_bank
                        cavespec_addresses[num_caves] = cs_file_ptr
                        num_caves++
                        if num_caves>MAX_CAVES {
                            num_caves--
                            break
                        }
                    }
                }
            }
        }

        if num_caves {
            ; parse the game parameters
            cs_file_bank = gameparams_bank
            cs_file_ptr = gameparams_address
            repeat {
                line = next_file_line_petscii()
                if line[0]=='['
                    return true
                uword argptr = 0
                ubyte isIndex = string.find(line, '=')
                if_cs {
                    argptr = line+isIndex+1
                    line[isIndex] = 0
                }
                if string.compare(line, "Name")==0
                    void string.copy(argptr, caveset_name)
                else if string.compare(line, "Author")==0
                    void string.copy(argptr, caveset_author)
                else if string.compare(line, "Levels")==0
                    num_levels = conv.str2ubyte(argptr)
            }
            return true
        }

        return false
    }

    sub parse_cave(ubyte levelindex) {
        cs_file_bank = cavespec_banks[levelindex]
        cs_file_ptr = cavespec_addresses[levelindex]
        str cave_name = "?" * 40
        str cave_description = "?" * 127

        const ubyte READ_SKIP = 0
        const ubyte READ_CAVE = 1
        const ubyte READ_OBJECTS = 2
        const ubyte READ_MAP = 3
        ubyte read_state = READ_CAVE
        uword lineptr
        uword argptr

        repeat {
            lineptr = next_file_line_petscii()
            uword isIndex
            if string.compare(lineptr, "[/cave]")==0
                return
            when read_state {
                READ_CAVE -> {
                    if string.compare(lineptr, "[map]")==0
                        read_state = READ_MAP
                    else if string.compare(lineptr, "[objects]")==0
                        read_state = READ_OBJECTS
                    else if lineptr[0]=='['
                        read_state = READ_SKIP
                    else {
                        argptr = 0
                        isIndex = string.find(lineptr, '=')
                        if_cs {
                            argptr = lineptr+isIndex+1
                            lineptr[isIndex] = 0
                        }

                        if string.compare(lineptr, "Name")==0 {
                            void string.copy(argptr, cave_name)
                            cave.name_ptr = cave_name
                        }
                        else if string.compare(lineptr, "Description")==0 {
                            void string.copy(argptr, cave_description)
                            cave.description_ptr = cave_description
                        }
                    }
                }
                READ_OBJECTS -> {
                    if string.compare(lineptr, "[/objects]")==0
                        read_state = READ_CAVE
                    else {
                        argptr = 0
                        isIndex = string.find(lineptr, '=')
                        if_cs {
                            argptr = lineptr+isIndex+1
                            lineptr[isIndex] = 0
                        }
                        if string.compare(lineptr, "Point")==0
                            parse_point()
                        else if string.compare(lineptr, "FillRect")==0
                            parse_fillrect()
                        else if string.compare(lineptr, "Line")==0
                            parse_line()
                        else if string.compare(lineptr, "Rectangle")==0
                            parse_rectangle()
                        else
                            sys.exit(1)     ; should never occur
                    }
                }
                READ_MAP -> {
                    if string.compare(lineptr, "[/map]")==0
                        read_state = READ_CAVE
                    else {
                        ; TODO read map line
                        txt.print("map line: ")
                        txt.print(lineptr)
                        txt.nl()
                    }
                }
            }

            uword[6] words = 0
            ubyte[6] arg_bytes = 0

            sub parse_point() {
                ; X Y OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                txt.print("point: ")
                txt.print_ub(arg_bytes[0])
                txt.chrout(',')
                txt.print_ub(arg_bytes[1])
                txt.chrout(',')
                txt.print(words[2])
                txt.nl()
            }
            sub parse_line() {
                ; X1 Y1 X2 Y2 OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                txt.print("line: ")
                txt.print_ub(arg_bytes[0])
                txt.chrout(',')
                txt.print_ub(arg_bytes[1])
                txt.chrout(',')
                txt.print_ub(arg_bytes[2])
                txt.chrout(',')
                txt.print_ub(arg_bytes[3])
                txt.chrout(',')
                txt.print(words[4])
                txt.nl()
            }
            sub parse_rectangle() {
                ; X1 Y1 X2 Y2 OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                txt.print("rect: ")
                txt.print_ub(arg_bytes[0])
                txt.chrout(',')
                txt.print_ub(arg_bytes[1])
                txt.chrout(',')
                txt.print_ub(arg_bytes[2])
                txt.chrout(',')
                txt.print_ub(arg_bytes[3])
                txt.chrout(',')
                txt.print(words[4])
                txt.nl()
            }
            sub parse_fillrect() {
                ; X1 Y1 X2 Y2 FILLOBJECT [optional: FILLOBJECT2]
                ; if 2 objects are specified, the first is the outline (Rect) object.
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                txt.print("fillrect: ")
                txt.print_ub(arg_bytes[0])
                txt.chrout(',')
                txt.print_ub(arg_bytes[1])
                txt.chrout(',')
                txt.print_ub(arg_bytes[2])
                txt.chrout(',')
                txt.print_ub(arg_bytes[3])
                txt.chrout(',')
                txt.print(words[4])
                if words[5] {
                    txt.chrout('+')
                    txt.print(words[5])
                }
                txt.nl()
            }

            sub split_words() {
                ubyte word_idx
                while @(argptr) {
                    words[word_idx] = argptr
                    word_idx++
                    cx16.r0L = string.find(argptr, ' ')
                    if_cc
                        return
                    argptr += cx16.r0L
                    @(argptr) = 0
                    argptr++
                }
            }
        }
    }

    sub ascii_to_petscii(uword lineptr) {
        repeat {
            cx16.r0L = @(lineptr)
            if_z
                return
            if cx16.r0L>=97 and cx16.r0L<=122
                cx16.r0L -= 32
            else if cx16.r0L>=65 and cx16.r0L<=90
                cx16.r0L |= 128
            @(lineptr)=cx16.r0L
            lineptr++
        }
    }

}

test_cave {

    sub load_test_cave() {
        cave.name_ptr = "test cave"
        cave.description_ptr = "this is a built-in test cave|to easily test things with"
        cave.intermission = false
        cave.width = 40
        cave.height = 22
        cave.cave_time_sec = 200
        cave.magicwall_millingtime_sec = 20
        cave.amoeba_slow_time_sec = 60
        cave.diamonds_needed = 10
        cave.initial_diamond_value = 1
        cave.extra_diamond_value = 2

        uword @zp ptr = &cave_data
        ubyte x
        ubyte y
        for y in 0 to cave.height-1 {
            for x in 0 to cave.width-1 {
                ubyte object = bdcff.translate_object(@(ptr))
                cave.set_tile(x, y, object, bdcff.translate_attr(@(ptr)))
                if object == objects.inboxclosed {
                    cave.player_x = x
                    cave.player_y = y
                }
                ptr++
            }
        }
    }

    cave_data:
    %asm {{
.text "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
.text "W           r                          W"
.text "W          dd                          W"
.text "W        dr r                          W"
.text "W       rd  d                          W"
.text "W       r   r                          W"
.text "W      d    d                          W"
.text "W     r     r         Q  Q  Q  Q       W"
.text "W......................................W"
.text "W          C  C  C  C                  W"
.text "W                                      W"
.text "Wssss...sssssssssssssssssssssssssssssssW"
.text "W          P                           W"
.text "W                        rrr%%%ddDD    W"
.text "W      .r.    .d.        ......d...    W"
.text "W      ...    ...        MMMMMMMMMM    W"
.text "W      . .   .. .x.                    W"
.text "W      . .   v. .                      W"
.text "W      . .   .. .         W  aa  W     W"
.text "W      . .    . .         WWWWWWWW     H"
.text "W      .C.    .Q.                      X"
.text "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
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
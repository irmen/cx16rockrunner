; Boulderdash Common File Format

%import conv
%import cave
%import objects

bdcff {
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
    ubyte[5] rand_seeds
    ubyte[5] cave_times
    ubyte[5] required_diamonds
    ubyte randomfill_obj1
    ubyte randomfill_obj2
    ubyte randomfill_obj3
    ubyte randomfill_obj4
    ubyte randomfill_prob1
    ubyte randomfill_prob2
    ubyte randomfill_prob3
    ubyte randomfill_prob4
    ubyte initial_fill

    ; TODO level file selector elsewhere that lets the player choose a .bd file to load here
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

    sub parse_cave(ubyte levelindex) {                      ; TODO add difficulty selector
        cs_file_bank = cavespec_banks[levelindex]
        cs_file_ptr = cavespec_addresses[levelindex]

        const ubyte READ_SKIP = 0
        const ubyte READ_CAVE = 1
        const ubyte READ_OBJECTS = 2
        const ubyte READ_MAP = 3
        ubyte read_state = READ_CAVE
        uword lineptr
        uword argptr

        cave.width = cave.MAX_CAVE_WIDTH as ubyte
        cave.height = cave.MAX_CAVE_HEIGHT
        cave.name[0] = 0
        cave.description[0] = 0
        cave.intermission = 0
        cave.cave_time_sec = 0
        cave.initial_diamond_value = 0
        cave.extra_diamond_value = 0
        cave.diamonds_needed = 0
        cave.magicwall_millingtime_sec = 0
        cave.amoeba_slow_time_sec = 0
        cave.slime_permeability = cave.DEFAULT_SLIME_PERMEABILITY
        rand_seeds = [0,0,0,0,0]
        cave_times = [0,0,0,0,0]
        required_diamonds = [0,0,0,0,0]
        randomfill_obj1 = 0
        randomfill_obj2 = 0
        randomfill_obj3 = 0
        randomfill_obj4 = 0
        randomfill_prob1 = 0
        randomfill_prob2 = 0
        randomfill_prob3 = 0
        randomfill_prob4 = 0
        initial_fill = 255       ; because 0 = space
        ubyte map_row

        repeat {
            lineptr = next_file_line_petscii()
            uword isIndex
            if string.compare(lineptr, "[/cave]")==0
                return
            when read_state {
                READ_CAVE -> {
                    if string.compare(lineptr, "[map]")==0 {
                        read_state = READ_MAP
                        map_row = 0
                    }
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
                            void string.copy(argptr, cave.name)
                        }
                        else if string.compare(lineptr, "Description")==0 {
                            void string.copy(argptr, cave.description)
                        }
                        else if string.compare(lineptr, "Size")==0 {
                            split_words()
                            cave.width = conv.str2ubyte(words[0])
                            cave.height = conv.str2ubyte(words[1])
                        }
                        else if string.compare(lineptr, "DiamondValue")==0 {
                            split_words()
                            cave.initial_diamond_value = conv.str2ubyte(words[0])
                            if words[1]
                                cave.extra_diamond_value = conv.str2ubyte(words[1])
                        }
                        else if string.compare(lineptr, "DiamondsRequired")==0 {
                            split_words()
                            for cx16.r2L in 0 to num_levels-1
                                required_diamonds[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
                        else if string.compare(lineptr, "CaveTime")==0 {
                            split_words()
                            for cx16.r2L in 0 to num_levels-1
                                cave_times[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
;                        else if string.compare(lineptr, "CaveDelay")==0 {
;                            split_words()
;                            ; TODO  number.  + what to do with this CaveDelay?
;                        }
;                        else if string.compare(lineptr, "Colors")==0 {
;                            split_words()
;                            ; TODO c64-style palette colors are not yet supported
;                        }
                        else if string.compare(lineptr, "RandSeed")==0 {
                            split_words()
                            for cx16.r2L in 0 to num_levels-1
                                rand_seeds[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
                        else if string.compare(lineptr, "RandomFill")==0 {
                            split_words()
                            if words[0] {
                                randomfill_obj1 = lsb(parse_object(words[0]))
                                randomfill_prob1 = conv.str2ubyte(words[1])
                            }
                            if words[2] {
                                randomfill_obj2 = lsb(parse_object(words[2]))
                                randomfill_prob2 = conv.str2ubyte(words[3])
                            }
                            if words[4] {
                                randomfill_obj3 = lsb(parse_object(words[4]))
                                randomfill_prob3 = conv.str2ubyte(words[5])
                            }
                            if words[6] {
                                randomfill_obj4 = lsb(parse_object(words[6]))
                                randomfill_prob4 = conv.str2ubyte(words[7])
                            }
                        }
                        else if string.compare(lineptr, "InitialFill")==0 {
                            split_words()
                            initial_fill = conv.str2ubyte(words[0])
                        }
                        else if string.compare(lineptr, "Intermission")==0 {
                            split_words()
                            if @(words[0])=='t'
                                cave.intermission=true
                        }
                        else if string.compare(lineptr, "MagicWallTime")==0 {
                            split_words()
                            cave.magicwall_millingtime_sec = conv.str2ubyte(words[0])
                        }
                        else if string.compare(lineptr, "AmoebaTime")==0 {
                            split_words()
                            cave.amoeba_slow_time_sec = conv.str2ubyte(words[0])
                        }
                        else if string.compare(lineptr, "SlimePermeability")==0 {
                            split_words()
                            uword numberStr = words[0]
                            numberStr[5] = 0
                            isIndex = string.find(numberStr, '.')
                            if_cs {
                                ; we assume the floating point value is always a multiple of 1/8ths so 0, 0.125, 0.250, etc etc up to 1.000
                                ; conversion to slime permeability byte is to set the number of bits equal to this factor.
                                if string.startswith(numberStr, "0.0")
                                    cave.slime_permeability = 0
                                else if string.startswith(numberStr, "0.125")
                                    cave.slime_permeability = %00000001
                                else if string.startswith(numberStr, "0.25")
                                    cave.slime_permeability = %00000011
                                else if string.startswith(numberStr, "0.375")
                                    cave.slime_permeability = %00000111
                                else if string.startswith(numberStr, "0.5")
                                    cave.slime_permeability = %00001111
                                else if string.startswith(numberStr, "0.625")
                                    cave.slime_permeability = %00011111
                                else if string.startswith(numberStr, "0.75")
                                    cave.slime_permeability = %00111111
                                else if string.startswith(numberStr, "0.875")
                                    cave.slime_permeability = %01111111
                                else if string.startswith(numberStr, "1.0")
                                    cave.slime_permeability = %11111111
                            } else {
                                ; it's just an integer
                                cave.slime_permeability = conv.str2ubyte(words[0])
                            }
                            txt.nl()
                        }
                        ;; else if string.compare(lineptr, "AmoebaGrowthProb")==0 { ... }
                        ;; else if string.compare(lineptr, "AmoebaThreshold")==0 { ... }
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
                        else if string.compare(lineptr, "Raster")==0
                            parse_raster()
                        else if string.compare(lineptr, "Add")==0
                            parse_add()
                        else
                            sys.reset_system()     ; should never occur
                    }
                }
                READ_MAP -> {
                    if string.compare(lineptr, "[/map]")==0
                        read_state = READ_CAVE
                    else {

                        ; TODO read map line
                        txt.print("map row ")
                        txt.print_ub0(map_row)
                        txt.chrout(':')
                        for cx16.r2L in 0 to cave.width-1 {
                            txt.chrout(lineptr[cx16.r2L])
                        }
                        txt.nl()
                        map_row++
                    }
                }
            }

            const ubyte MAX_WORDS = 8
            uword[MAX_WORDS] words
            ubyte[MAX_WORDS] arg_bytes

            words = [0,0,0,0,0,0,0,0]
            arg_bytes = [0,0,0,0,0,0,0,0]

            sub parse_point() {
                ; X Y OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                cx16.r0 = parse_object(words[2])
                draw_single(cx16.r0, arg_bytes[0], arg_bytes[1])
            }

            sub parse_line() {
                ; X1 Y1 X2 Y2 OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                cx16.r0 = parse_object(words[4])
                draw_line(cx16.r0, arg_bytes[0], arg_bytes[1], arg_bytes[2], arg_bytes[3])
            }

            sub parse_rectangle() {
                ; X1 Y1 X2 Y2 OBJECT
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                cx16.r0 = parse_object(words[4])
                draw_rectangle(cx16.r0, arg_bytes[0], arg_bytes[1], arg_bytes[2], arg_bytes[3], $00ff)
            }

            sub parse_fillrect() {
                ; X1 Y1 X2 Y2 FILLOBJECT [optional: FILLOBJECT2]
                ; if 2 objects are specified, the first is the outline (Rect) object.
                split_words()
                arg_bytes[0] = conv.str2ubyte(words[0])
                arg_bytes[1] = conv.str2ubyte(words[1])
                arg_bytes[2] = conv.str2ubyte(words[2])
                arg_bytes[3] = conv.str2ubyte(words[3])
                cx16.r0 = parse_object(words[4])
                cx16.r1 = $00ff
                if words[5]
                    cx16.r1 = parse_object(words[5])
                draw_rectangle(cx16.r0, arg_bytes[0], arg_bytes[1], arg_bytes[2], arg_bytes[3], cx16.r1)
            }

            sub parse_raster() {
                ; TODO x y numberx numbery stepx stepy object
                ; TODO figure out what this is
            }

            sub parse_add() {
                ; TODO incx incy searchobject addobject [replaceobject]
                ; TODO figure out what this is, only used in Boulderdash02?
            }

            sub parse_object(str name) -> uword {
                str[] names = [
                    "SPACE",
                    "DIRT",
                    "WALL",
                    "MAGICWALL",
                    "OUTBOX",
                    "HIDDENOUTBOX",
                    "STEELWALL",
                    "FIREFLYl",
                    "FIREFLYu",
                    "FIREFLYr",
                    "FIREFLYd",
                    "BOULDER",
                    "BOULDERf",
                    "DIAMOND",
                    "DIAMONDf",
                    "INBOX",
                    "HEXPANDINGWALL",
                    "VEXPANDINGWALL",
                    "EXPANDINGWALL",
                    "BUTTERFLYl",
                    "BUTTERFLYu",
                    "BUTTERFLYr",
                    "BUTTERFLYd",
                    "AMOEBA",
                    "SLIME"
                ]
                ubyte[len(names)] object = [
                    objects.space,
                    objects.dirt,
                    objects.wall,
                    objects.magicwall,
                    objects.outboxclosed,
                    objects.outboxhidden,
                    objects.steel,
                    objects.firefly,
                    objects.firefly,
                    objects.firefly,
                    objects.firefly,
                    objects.boulder,
                    objects.boulder,
                    objects.diamond,
                    objects.diamond,
                    objects.inboxclosed,
                    objects.horizexpander,
                    objects.vertexpander,
                    objects.bothexpander,
                    objects.butterfly,
                    objects.butterfly,
                    objects.butterfly,
                    objects.butterfly,
                    objects.amoeba,
                    objects.slime
                ]
                ubyte[len(names)] attrs = [
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    cave.ATTR_MOVING_LEFT,
                    cave.ATTR_MOVING_UP,
                    cave.ATTR_MOVING_RIGHT,
                    cave.ATTR_MOVING_DOWN,
                    0,
                    cave.ATTR_FALLING,
                    0,
                    cave.ATTR_FALLING,
                    0,
                    0,
                    0,
                    0,
                    cave.ATTR_MOVING_LEFT,
                    cave.ATTR_MOVING_UP,
                    cave.ATTR_MOVING_RIGHT,
                    cave.ATTR_MOVING_DOWN,
                    0,
                    0
                ]
                for cx16.r2L in 0 to len(names)-1 {
                    if string.compare(name, names[cx16.r2L])==0
                        return mkword(attrs[cx16.r2L], object[cx16.r2L])
                }
                sys.reset_system()     ; should never happen, all object names should be recognised
            }

            sub split_words() {
                ubyte word_idx
                while @(argptr) and word_idx<len(words) {
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

    sub draw_single(uword objattr, ubyte x, ubyte y) {
        cave.set_tile(x, y, lsb(objattr), msb(objattr))
        if lsb(objattr)==objects.inboxclosed or lsb(objattr)==objects.rockfordbirth {
            cave.player_x = x
            cave.player_y = y
        }
    }

    sub draw_rectangle(uword objattr, ubyte x1, ubyte y1, ubyte x2, ubyte y2, uword fillobjattr) {
        draw_line(objattr, x1, y1, x2, y1)
        draw_line(objattr, x1, y2, x2, y2)
        draw_line(objattr, x1, y1, x1, y2)
        draw_line(objattr, x2, y1, x2, y2)
        if lsb(fillobjattr)!=255 {
            ubyte y
            for y in y1 + 1 to y2-1
                draw_line(fillobjattr, x1+1, y, x2-1, y)
        }
    }

    sub draw_line(uword objattr, ubyte x1, ubyte y1, ubyte x2, ubyte y2) {
        ; line can be horizontal, vertical, or 45 degree diagonal.
        ; other slopes are not supported!
        byte dx = -1
        byte dy = -1
        if x2>x1
            dx = 1
        else if x2==x1
            dx = 0
        if y2>y1
            dy = 1
        else if y2==y1
            dy = 0
        while x1!=x2 and y1!=y2 {
            draw_single(objattr, x1, y1)
            x1 += dx as ubyte
            y1 += dy as ubyte
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
            'V' -> return objects.bothexpander
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
            ; note: there is no 1 character code for boulder+falling and diamond+faling.
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
}

test_cave {

    sub load_test_cave() {
        cave.name = "test cave"
        cave.description = "this is a built-in test cave|to easily test things with"
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
.text "W      .r.    .d...      ......d...    W"
.text "W      ...    ...x...    MMMMMMMMMM    W"
.text "W      . .   .. ...V.                  W"
.text "W      . .   v. . ...                  W"
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
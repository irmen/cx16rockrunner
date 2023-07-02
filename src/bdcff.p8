; Boulderdash Common File Format loader and parsing

%import conv
%import cave
%import objects

bdcff {
    const ubyte FILENAMES_BANK = 2
    const ubyte FILEDATA_BANK = 3
    ubyte cs_file_bank
    uword @zp cs_file_ptr

    const ubyte MAX_CAVES = 20
    ubyte num_caves
    ubyte num_difficulty_levels
    str caveset_name = " " * 40
    str caveset_author = " " * 40
    str caveset_filename = " " * 32

    ; pointers into the BDCFF caveset file:
    ubyte gameparams_bank
    uword gameparams_address
    ubyte[MAX_CAVES] cavespec_banks
    uword[MAX_CAVES] cavespec_addresses
    ubyte[5] rand_seeds
    ubyte[5] cave_times
    ubyte[5] diamonds_needed

    sub load_caveset(str filename) -> bool {
        caveset_filename = filename     ; make a copy, because we switch ram banks
        cs_file_bank = 0
        cs_file_ptr = 0
        cx16.rambank(FILEDATA_BANK)
        diskio.chdir("caves")
        cx16.r8 = diskio.load_raw(caveset_filename, $a000)
        diskio.chdir("..")
        if cx16.r8!=0 {
            @(cx16.r8) = 0
            cs_file_bank = FILEDATA_BANK
            cs_file_ptr = $a000
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
        num_difficulty_levels = 0
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
                    if line[1]=='/' and line=="[/game]"
                        break
                    else if line=="[game]" {
                        gameparams_bank = cs_file_bank
                        gameparams_address = cs_file_ptr
                    }
                    else if line=="[cave]" {
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
                if line=="Name"
                    void string.copy(argptr, caveset_name)
                else if line=="Author"
                    void string.copy(argptr, caveset_author)
                else if line=="Levels"
                    num_difficulty_levels = conv.str2ubyte(argptr)
            }
            ; return true
        }

        return false
    }

    sub parse_cave(ubyte level, ubyte difficulty) {
        cs_file_bank = cavespec_banks[level-1]
        cs_file_ptr = cavespec_addresses[level-1]
        difficulty = clamp(difficulty, 1, num_difficulty_levels)

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
        cave.intermission = false
        cave.cave_time_sec = 0
        cave.initial_diamond_value = 0
        cave.extra_diamond_value = 0
        cave.diamonds_needed = 0
        cave.magicwall_millingtime_sec = 0
        cave.amoeba_slow_time_sec = 0
        cave.slime_permeability = 0

        rand_seeds = [0,0,0,0,0]
        cave_times = [0,0,0,0,0]
        diamonds_needed = [0,0,0,0,0]
        ubyte map_row
        bool size_specified = false
        ubyte cave_speed_from_cavedata = 0

        ; fill cave with dirt
        draw_rectangle(objects.dirt, 0, 0, cave.MAX_CAVE_WIDTH-1, cave.MAX_CAVE_HEIGHT-1, objects.dirt)

        repeat {
            lineptr = next_file_line_petscii()
            uword isIndex
            if lineptr=="[/cave]" {
                validate_size()
                cave.diamonds_needed = diamonds_needed[difficulty-1]
                cave.cave_time_sec = cave_times[difficulty-1]
                if cave_speed_from_cavedata
                    cave.cave_speed = cave_speed_from_cavedata
                else if cave.intermission
                    cave.cave_speed = cave.CAVE_SPEED_INTERMISSION - difficulty/2
                else
                    cave.cave_speed = cave.CAVE_SPEED_NORMAL - difficulty/2
                return
            }
            when read_state {
                READ_CAVE -> {
                    if lineptr=="[map]" {
                        read_state = READ_MAP
                        map_row = 0
                    }
                    else if lineptr=="[objects]"
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

                        if lineptr=="Name" {
                            void string.copy(argptr, cave.name)
                        }
                        else if lineptr=="Description" {
                            void string.copy(argptr, cave.description)
                        }
                        else if lineptr=="Size" {
                            split_words()
                            cave.width = conv.str2ubyte(words[0])
                            cave.height = conv.str2ubyte(words[1])
                            size_specified = true
                        }
                        else if lineptr=="DiamondValue" {
                            split_words()
                            cave.initial_diamond_value = conv.str2ubyte(words[0])
                            if words[1]
                                cave.extra_diamond_value = conv.str2ubyte(words[1])
                        }
                        else if lineptr=="DiamondsRequired" {
                            split_words()
                            for cx16.r2L in 0 to num_difficulty_levels-1
                                diamonds_needed[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
                        else if lineptr=="CaveTime" {
                            split_words()
                            for cx16.r2L in 0 to num_difficulty_levels-1
                                cave_times[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
                        else if lineptr=="CaveDelay" {
                            split_words()
                            cave_speed_from_cavedata = conv.str2ubyte(words[0])
                        }
;                        else if lineptr=="Colors" {
;                            split_words()
;                            ; TODO c64-style palette colors are not yet supported, would require a different tileset
;                        }
                        else if lineptr=="RandSeed" {
                            split_words()
                            for cx16.r2L in 0 to num_difficulty_levels-1
                                rand_seeds[cx16.r2L] = conv.str2ubyte(words[cx16.r2L])
                        }
                        else if lineptr=="RandomFill" {
                            uword randomfill_objattr1 = 0
                            uword randomfill_objattr2 = 0
                            uword randomfill_objattr3 = 0
                            uword randomfill_objattr4 = 0
                            ubyte randomfill_prob1 = 0
                            ubyte randomfill_prob2 = 0
                            ubyte randomfill_prob3 = 0
                            ubyte randomfill_prob4 = 0
                            split_words()
                            if words[0] {
                                randomfill_objattr1 = parse_object(words[0])
                                randomfill_prob1 = conv.str2ubyte(words[1])
                            }
                            if words[2] {
                                randomfill_objattr2 = parse_object(words[2])
                                randomfill_prob2 = conv.str2ubyte(words[3])
                            }
                            if words[4] {
                                randomfill_objattr3 = parse_object(words[4])
                                randomfill_prob3 = conv.str2ubyte(words[5])
                            }
                            if words[6] {
                                randomfill_objattr4 = parse_object(words[6])
                                randomfill_prob4 = conv.str2ubyte(words[7])
                            }

                            bdrandom_seed1 = 0
                            bdrandom_seed2 = rand_seeds[difficulty-1]
                            ubyte x
                            ubyte y
                            for y in 1 to cave.height-2 {
                                for x in 0 to cave.width-1 {
                                    cx16.r5 = objects.dirt
                                    ubyte rnd = bdrandom()
                                    if rnd < randomfill_prob1
                                        cx16.r5 = randomfill_objattr1
                                    if rnd < randomfill_prob2
                                        cx16.r5 = randomfill_objattr2
                                    if rnd < randomfill_prob3
                                        cx16.r5 = randomfill_objattr3
                                    if rnd < randomfill_prob4
                                        cx16.r5 = randomfill_objattr4
                                    draw_single(cx16.r5, x, y)
                                }
                            }
                        }
                        else if lineptr=="InitialFill" {
                            validate_size()
                            split_words()
                            cx16.r0 = parse_object(words[0])
                            draw_rectangle(cx16.r0, 1, 1, cave.width-2, cave.height-2, cx16.r0)
                        }
                        else if lineptr=="Intermission" {
                            split_words()
                            if @(words[0])=='t'
                                cave.intermission=true
                        }
                        else if lineptr=="MagicWallTime" {
                            split_words()
                            cave.magicwall_millingtime_sec = conv.str2ubyte(words[0])
                        }
                        else if lineptr=="AmoebaTime" {
                            split_words()
                            cave.amoeba_slow_time_sec = conv.str2ubyte(words[0])
                        }
                        else if lineptr=="SlimePermeability" {
                            split_words()
                            uword numberStr = words[0]
                            numberStr[5] = 0
                            isIndex = string.find(numberStr, '.')
                            if_cs {
                                ; we assume the floating point value is always a multiple of 1/8ths so 0, 0.125, 0.250, etc etc up to 1.000
                                ; conversion to slime permeability byte is to set the number of bits equal to this factor.
                                if string.startswith(numberStr, "0.0")
                                    cave.slime_permeability = %11111111
                                else if string.startswith(numberStr, "0.125")
                                    cave.slime_permeability = %11111110
                                else if string.startswith(numberStr, "0.25")
                                    cave.slime_permeability = %11111100
                                else if string.startswith(numberStr, "0.375")
                                    cave.slime_permeability = %11111000
                                else if string.startswith(numberStr, "0.5")
                                    cave.slime_permeability = %11110000
                                else if string.startswith(numberStr, "0.625")
                                    cave.slime_permeability = %11100000
                                else if string.startswith(numberStr, "0.75")
                                    cave.slime_permeability = %11000000
                                else if string.startswith(numberStr, "0.875")
                                    cave.slime_permeability = %10000000
                                else if string.startswith(numberStr, "1.0")
                                    cave.slime_permeability = %00000000
                            } else {
                                ; it's just an integer
                                cave.slime_permeability = conv.str2ubyte(words[0])
                            }
                        }
                        ;; else if lineptr=="AmoebaGrowthProb" { ...TODO... }
                        ;; else if lineptr=="AmoebaThreshold" { ...TODO... }
                    }
                }
                READ_OBJECTS -> {
                    if lineptr=="[/objects]" {
                        ; draw the initial border of steel tiles
                        draw_rectangle(objects.steel, 0, 0, cave.width-1, cave.height-1, $00ff)
                        read_state = READ_CAVE
                    }
                    else {
                        argptr = 0
                        isIndex = string.find(lineptr, '=')
                        if_cs {
                            argptr = lineptr+isIndex+1
                            lineptr[isIndex] = 0
                        }
                        if lineptr=="Point"
                            parse_point()
                        else if lineptr=="FillRect"
                            parse_fillrect()
                        else if lineptr=="Line"
                            parse_line()
                        else if lineptr=="Rectangle"
                            parse_rectangle()
                        else if lineptr=="Raster"
                            parse_raster()
                        else if lineptr=="Add"
                            parse_add(false)
                        else if lineptr=="AddBackward"
                            parse_add(true)
                        else
                            main.error_abort($82)  ; should never occur!
                    }
                }
                READ_MAP -> {
                    if lineptr=="[/map]" {
                        read_state = READ_CAVE
                        size_specified = true
                    }
                    else {
                        ubyte map_column=0
                        while @(lineptr) {
                            cx16.r0L = @(lineptr)
                            cx16.r1 = mkword(translate_attr(cx16.r0L), translate_object(cx16.r0L))
                            draw_single(cx16.r1, map_column, map_row)
                            map_column++
                            lineptr++
                        }
                        map_row++
                        ; adjust cave size from the map that is being read in
                        cave.width = map_column
                        cave.height = map_row
                    }
                }
            }

            const ubyte MAX_WORDS = 8
            uword[MAX_WORDS] words
            ubyte[MAX_WORDS] arg_bytes

            words = [0,0,0,0,0,0,0,0]
            arg_bytes = [0,0,0,0,0,0,0,0]

            sub validate_size() {
                if not size_specified {
                    if cave.intermission {
                        cave.width = 20
                        cave.height = 12
                    } else {
                        cave.width = cave.MAX_CAVE_WIDTH as ubyte
                        cave.height = cave.MAX_CAVE_HEIGHT
                    }
                }

                ubyte i
                for i in cave.width to cave.MAX_CAVE_WIDTH-1
                    draw_line(objects.steel, i, 0, i, cave.MAX_CAVE_WIDTH-1)
                for i in cave.height to cave.MAX_CAVE_HEIGHT-1
                    draw_line(objects.steel, 0, i, cave.MAX_CAVE_HEIGHT-1, i)
            }

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
                uword filler = parse_object(words[4])
                uword border = filler
                if words[5]
                    filler = parse_object(words[5])
                draw_rectangle(border, arg_bytes[0], arg_bytes[1], arg_bytes[2], arg_bytes[3], filler)
            }

            sub parse_raster() {
                ; this draws an evenly spaced grid of the given object
                ; only used in Boulderdash02?
                ; x y numberx numbery stepx stepy object
                split_words()
                ubyte startx = conv.str2ubyte(words[0])
                ubyte starty = conv.str2ubyte(words[1])
                ubyte nx = conv.str2ubyte(words[2])
                ubyte ny = conv.str2ubyte(words[3])
                ubyte stepx = conv.str2ubyte(words[4])
                ubyte stepy = conv.str2ubyte(words[5])
                uword object = parse_object(words[6])

                cx16.r0L = startx
                cx16.r1L = starty
                repeat ny {
                    repeat nx {
                        draw_single(object, cx16.r0L, cx16.r1L)
                        cx16.r0L += stepx
                    }
                    cx16.r0L = startx
                    cx16.r1L += stepy
                }
            }

            sub parse_add(bool backwards) {
                ; "find every object, and put fill_element next to it. relative coordinates dx,dy"
                ; backwards = scan from bottom to top
                ; only used in Boulderdash02?
                ; incx incy searchobject addobject [replaceobject]
                ; TODO replaceobject = unknown what this does :-|  replacing searchobject by something else ? doesn't seem very useful
                split_words()
                byte incx = conv.str2byte(words[0])
                byte incy = conv.str2byte(words[1])
                uword search = parse_object(words[2])
                uword replace = parse_object(words[3])
                if backwards {
                    for cx16.r1L in 0 to cave.height-1 {
                        for cx16.r0L in 0 to cave.width-1 {
                            if @(cave.cells + cx16.r1L*cave.MAX_CAVE_WIDTH + cx16.r0L) == lsb(search)
                                draw_single(replace, cx16.r0L+incx as ubyte, cx16.r1L+incy as ubyte)
                        }
                    }
                } else {
                    for cx16.r1L in cave.height-1 downto 0 {
                        for cx16.r0L in cave.width-1 downto 0 {
                            if @(cave.cells + cx16.r1L*cave.MAX_CAVE_WIDTH + cx16.r0L) == lsb(search)
                                draw_single(replace, cx16.r0L+incx as ubyte, cx16.r1L+incy as ubyte)
                        }
                    }
                }
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

                ; should never happen, all object names should be recognised
                main.error_abort($83)  ; should never occur!
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
        while x1!=x2 or y1!=y2 {
            draw_single(objattr, x1, y1)
            x1 += dx as ubyte
            y1 += dy as ubyte
        }
        draw_single(objattr, x1, y1)
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
            ; note: there is no 1 character code for boulder+falling and diamond+falling.
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

    ubyte @shared bdrandom_seed1
    ubyte @shared bdrandom_seed2
    sub bdrandom() -> ubyte {
        ; the pseudo random generator that Boulderdash C64 used
        ; see https://www.elmerproductions.com/sp/peterb/insideBoulderdash.html#Random%20numbers
        ubyte @shared temp1
        ubyte @shared temp2
        %asm {{
            lda  p8_bdrandom_seed1
            ror  a
            ror  a
            and  #$80
            sta  p8_temp1
            lda  p8_bdrandom_seed2
            ror  a
            and  #$7f
            sta  p8_temp2
            lda  p8_bdrandom_seed2
            ror  a
            ror  a
            and  #$80
            clc
            adc  p8_bdrandom_seed2
            adc  #$13
            sta  p8_bdrandom_seed2
            lda  p8_bdrandom_seed1
            adc  p8_temp1
            adc  p8_temp2
            sta  p8_bdrandom_seed1
            rts
        }}
    }

}
